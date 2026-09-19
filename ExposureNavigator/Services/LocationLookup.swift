import Foundation
import MapKit
import CoreLocation
import Observation

struct LocationSuggestion: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var subtitle: String
    var completion: MKLocalSearchCompletion
}
@Observable @MainActor
final class AddressSearchService: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    var suggestions: [LocationSuggestion] = []
    var errorMessage: String?
    override init() { super.init(); completer.resultTypes = [.address, .pointOfInterest]; completer.delegate = self }
    func search(_ query: String) {
        suggestions = []; errorMessage = nil
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { completer.cancel(); return }
        completer.queryFragment = query
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.prefix(6).map { .init(title: $0.title, subtitle: $0.subtitle, completion: $0) }
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []; errorMessage = "Suggestions unavailable. Tap Search to find matching places."
    }
    func resolve(_ suggestion: LocationSuggestion) async throws -> ActivityLocation {
        let response = try await MKLocalSearch(request: .init(completion: suggestion.completion)).start()
        guard let item = response.mapItems.first else { throw EnvironmentalDataError.invalidLocation }
        return try place(item)
    }
    func lookup(_ address: String) async throws -> [ActivityLocation] {
        try await MapKitPlaceSearch().lookup(address)
    }
    func resolveAddress(_ address: String) async throws -> ActivityLocation {
        guard var location = try await lookup(address).first else { throw EnvironmentalDataError.invalidLocation }
        if address.range(of: #"^\d{5}$"#, options: .regularExpression) != nil, !location.formattedAddress.isEmpty { location.name = location.formattedAddress }
        return location
    }
    private func place(_ item: MKMapItem) throws -> ActivityLocation {
        try MapKitPlaceSearch.place(item)
    }
}

struct MapKitPlaceSearch: PlaceSearching {
    func lookup(_ address: String) async throws -> [ActivityLocation] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        let response = try await MKLocalSearch(request: request).start()
        let matches = response.mapItems.prefix(6).compactMap { try? Self.place($0) }
        guard !matches.isEmpty else { throw EnvironmentalDataError.invalidLocation }
        return Array(matches)
    }

    static func place(_ item: MKMapItem) throws -> ActivityLocation {
        guard let location = item.placemark.location else { throw EnvironmentalDataError.invalidLocation }
        return .init(name: item.name ?? "Selected place", formattedAddress: [item.placemark.subThoroughfare, item.placemark.thoroughfare, item.placemark.locality, item.placemark.administrativeArea, item.placemark.postalCode].compactMap { $0 }.joined(separator: " "), latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, timeZoneIdentifier: item.timeZone?.identifier)
    }
}

@Observable @MainActor
final class LocationManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var authorization: CLAuthorizationStatus
    var location: CLLocation?
    var placeName = "Your location"
    override init() { authorization = manager.authorizationStatus; super.init(); manager.delegate = self }
    func requestIfAuthorized() { if authorization == .authorizedWhenInUse || authorization == .authorizedAlways { manager.requestLocation() } }
    func request() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { requestIfAuthorized() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways { manager.requestLocation() }
        else { location = nil }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        if let location {
            Task { if let place = try? await CLGeocoder().reverseGeocodeLocation(location).first { placeName = [place.locality, place.administrativeArea].compactMap { $0 }.joined(separator: ", ") } }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
