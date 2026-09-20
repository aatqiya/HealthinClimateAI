import Foundation

protocol NYCObserving: Sendable {
    func observations(latitude: Double, longitude: Double) async throws -> (site: NYCMonitorSite, hours: [Date: Double])
}

/// Hourly observed PM2.5 from NYC DOHMH / Queens College street-level monitors.
/// No health context enters this request. Missing hours are omitted, never invented.
struct NYCMonitorProvider: NYCObserving {
    var session: URLSession = .shared
    var readingsURL: URL = NYCMonitorCatalog.readingsURL

    func observations(latitude: Double, longitude: Double) async throws -> (site: NYCMonitorSite, hours: [Date: Double]) {
        guard let site = NYCMonitorCatalog.nearest(latitude: latitude, longitude: longitude) else {
            throw EnvironmentalDataError.invalidLocation
        }
        var request = URLRequest(url: readingsURL)
        request.timeoutInterval = 20
        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 { throw EnvironmentalDataError.rateLimited }
                guard (200..<300).contains(http.statusCode) else { throw EnvironmentalDataError.network(underlying: "HTTP \(http.statusCode)") }
            }
            data = body
        } catch let error as EnvironmentalDataError {
            throw error
        } catch let error as URLError {
            throw error.code == .timedOut ? EnvironmentalDataError.timedOut : EnvironmentalDataError.network(underlying: error.localizedDescription)
        } catch {
            throw EnvironmentalDataError.malformedResponse
        }
        guard let text = String(data: data, encoding: .utf8) else { throw EnvironmentalDataError.malformedResponse }
        let hours = NYCMonitorCSV.hours(from: NYCMonitorCSV.parse(text), site: site)
        guard !hours.isEmpty else { throw EnvironmentalDataError.forecastUnavailable }
        return (site, hours)
    }
}

enum NYCObservationMerge {
    static func apply(forecast: EnvironmentalTimeSeries, site: NYCMonitorSite, hours: [Date: Double]) -> EnvironmentalTimeSeries {
        guard !hours.isEmpty else { return forecast }
        var byHour: [Date: EnvironmentalSample] = [:]
        for sample in forecast.samples { byHour[sample.timestamp] = sample }
        for (start, pm25) in hours {
            var sample = byHour[start] ?? EnvironmentalSample(timestamp: start)
            sample.pm25 = pm25
            byHour[start] = sample
        }
        var series = forecast
        series.samples = byHour.values.sorted { $0.timestamp < $1.timestamp }
        series.source = "\(forecast.source) + \(NYCMonitorCatalog.sourceName) (\(site.name))"
        series.observedPM25Site = site.name
        series.observationAttributionURL = NYCMonitorCatalog.attribution
        return series
    }
}

/// Forecast remains authoritative for future hours and for ozone/heat.
/// NYC monitors overlay observed PM2.5 when the place is in the city.
struct MergedEnvironmentalProvider: EnvironmentalDataProviding {
    var forecast: EnvironmentalDataProviding = OpenMeteoProvider()
    var observations: NYCObserving = NYCMonitorProvider()

    func fetchConditions(latitude: Double, longitude: Double, range: ClosedRange<Date>) async throws -> EnvironmentalTimeSeries {
        let forecastSeries = try await forecast.fetchConditions(latitude: latitude, longitude: longitude, range: range)
        guard NYCMonitorCatalog.contains(latitude: latitude, longitude: longitude) else { return forecastSeries }
        do {
            let observed = try await observations.observations(latitude: latitude, longitude: longitude)
            return NYCObservationMerge.apply(forecast: forecastSeries, site: observed.site, hours: observed.hours)
        } catch {
            return forecastSeries
        }
    }
}
