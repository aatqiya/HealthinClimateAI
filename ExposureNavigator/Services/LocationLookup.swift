import Foundation
import MapKit
import CoreLocation
import Observation

struct LocationSuggestion: Identifiable, Hashable { let id=UUID(); var title:String; var subtitle:String; var completion:MKLocalSearchCompletion }
@Observable @MainActor
final class AddressSearchService:NSObject,MKLocalSearchCompleterDelegate {
    private let completer=MKLocalSearchCompleter(); var suggestions:[LocationSuggestion]=[]
    override init(){super.init();completer.resultTypes=[.address,.pointOfInterest];completer.delegate=self}
    func search(_ query:String){ suggestions=[]; completer.queryFragment=query }
    func completerDidUpdateResults(_ c:MKLocalSearchCompleter){suggestions=c.results.prefix(6).map{.init(title:$0.title,subtitle:$0.subtitle,completion:$0)}}
    func completer(_ c:MKLocalSearchCompleter,didFailWithError error:Error){suggestions=[]}
    func resolve(_ suggestion:LocationSuggestion) async throws -> ActivityLocation { let r=MKLocalSearch.Request(completion:suggestion.completion);let response=try await MKLocalSearch(request:r).start();guard let item=response.mapItems.first,let p=item.placemark.location else{throw EnvironmentalDataError.invalidLocation};return .init(name:item.name ?? suggestion.title,formattedAddress:[item.placemark.subThoroughfare,item.placemark.thoroughfare,item.placemark.locality,item.placemark.administrativeArea,item.placemark.postalCode].compactMap{$0}.joined(separator:" "),latitude:p.coordinate.latitude,longitude:p.coordinate.longitude,timeZoneIdentifier:item.timeZone?.identifier) }
    func resolveAddress(_ address:String) async throws -> ActivityLocation { let r=MKLocalSearch.Request();r.naturalLanguageQuery=address;let response=try await MKLocalSearch(request:r).start();guard let item=response.mapItems.first,let p=item.placemark.location else{throw EnvironmentalDataError.invalidLocation};return .init(name:item.name ?? address,formattedAddress:[item.placemark.subThoroughfare,item.placemark.thoroughfare,item.placemark.locality,item.placemark.administrativeArea,item.placemark.postalCode].compactMap{$0}.joined(separator:" "),latitude:p.coordinate.latitude,longitude:p.coordinate.longitude,timeZoneIdentifier:item.timeZone?.identifier) }
}
@Observable @MainActor
final class LocationManager:NSObject,CLLocationManagerDelegate {
    private let manager=CLLocationManager(); var authorization:CLAuthorizationStatus; var location:CLLocation?; var placeName="Your location"
    override init(){authorization=manager.authorizationStatus;super.init();manager.delegate=self}
    func request(){manager.requestWhenInUseAuthorization();manager.requestLocation()}
    func locationManagerDidChangeAuthorization(_ m:CLLocationManager){authorization=m.authorizationStatus;if authorization==.authorizedWhenInUse||authorization==.authorizedAlways{m.requestLocation()}}
    func locationManager(_ m:CLLocationManager,didUpdateLocations locations:[CLLocation]){location=locations.last;if let l=location{Task{if let p=try? await CLGeocoder().reverseGeocodeLocation(l).first{placeName=[p.locality,p.administrativeArea].compactMap{$0}.joined(separator:", ")}}}}
    func locationManager(_ m:CLLocationManager,didFailWithError error:Error){}
}
