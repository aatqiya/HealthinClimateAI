import Foundation

struct NYCMonitorSite: Equatable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
}

enum NYCMonitorCatalog {
    static let attribution = "https://a816-dohbesp.nyc.gov/IndicatorPublic/data-features/realtime-air-quality/"
    static let readingsURL = URL(string: "https://raw.githubusercontent.com/nychealth/nyccas-data/main/portal/view.csv")!
    static let sourceName = "NYC DOHMH / Queens College street-level PM2.5 monitors"

    /// Approximate NYC bounding box. Locations outside it never request monitors.
    static let latitudeRange = 40.477...40.917
    static let longitudeRange = -74.259 ... -73.700

    static let sites: [NYCMonitorSite] = [
        .init(name: "Mott Haven", latitude: 40.80649, longitude: -73.92249),
        .init(name: "Hunt's Point", latitude: 40.81909, longitude: -73.88566),
        .init(name: "Cross Bronx Expy", latitude: 40.84517, longitude: -73.90614),
        .init(name: "BQE", latitude: 40.7028, longitude: -73.96082),
        .init(name: "Manhattan Bridge", latitude: 40.71651, longitude: -73.997),
        .init(name: "Williamsburg Bridge", latitude: 40.71807, longitude: -73.98606),
        .init(name: "FDR", latitude: 40.72229, longitude: -73.97465),
        .init(name: "Broadway/35th St", latitude: 40.75069, longitude: -73.98783),
        .init(name: "Midtown West", latitude: 40.75514, longitude: -73.99086),
        .init(name: "Queensboro Bridge", latitude: 40.76123, longitude: -73.96389),
        .init(name: "Hamilton Bridge", latitude: 40.84654, longitude: -73.93302),
        .init(name: "Van Wyck", latitude: 40.69015, longitude: -73.80908),
        .init(name: "Glendale", latitude: 40.70574, longitude: -73.88627),
        .init(name: "Queens College", latitude: 40.73711, longitude: -73.82156),
        .init(name: "SI Expwy", latitude: 40.60921, longitude: -74.15118)
    ]

    static func contains(latitude: Double, longitude: Double) -> Bool {
        latitudeRange.contains(latitude) && longitudeRange.contains(longitude)
    }

    static func nearest(latitude: Double, longitude: Double) -> NYCMonitorSite? {
        guard contains(latitude: latitude, longitude: longitude) else { return nil }
        return sites.min { distanceMeters(latitude, longitude, $0.latitude, $0.longitude) < distanceMeters(latitude, longitude, $1.latitude, $1.longitude) }
    }

    static func matches(_ readingName: String, site: NYCMonitorSite) -> Bool {
        normalize(readingName) == normalize(site.name)
    }

    static func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func distanceMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * atan2(sqrt(a), sqrt(1 - a))
    }
}

struct NYCMonitorReading: Equatable {
    var siteName: String
    var start: Date
    var pm25: Double
}

enum NYCMonitorCSV {
    /// Portal clock matches `timeofday` (Eastern wall time), not UTC despite some archive notes.
    static func parse(_ text: String, timeZone: TimeZone = TimeZone(identifier: "America/New_York") ?? .current) -> [NYCMonitorReading] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        var readings: [NYCMonitorReading] = []
        for line in text.split(whereSeparator: \.isNewline).dropFirst() {
            let columns = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard columns.count >= 5, let start = formatter.date(from: columns[2]), let pm25 = Double(columns[4]), pm25.isFinite, pm25 >= 0 else { continue }
            readings.append(.init(siteName: columns[0], start: start, pm25: pm25))
        }
        return readings
    }

    static func hours(from readings: [NYCMonitorReading], site: NYCMonitorSite) -> [Date: Double] {
        var hours: [Date: Double] = [:]
        for reading in readings where NYCMonitorCatalog.matches(reading.siteName, site: site) {
            hours[reading.start] = reading.pm25
        }
        return hours
    }
}
