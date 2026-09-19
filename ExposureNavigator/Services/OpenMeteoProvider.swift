import Foundation

/// Open-Meteo Air Quality + Weather forecast.
/// No API key required. Hourly values are provider-documented as values for the
/// hour beginning at the given timestamp.
struct OpenMeteoProvider: EnvironmentalDataProviding {
    static let sourceName = "Open-Meteo Air Quality & Weather Forecast"
    static let attribution = "https://open-meteo.com"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchConditions(
        latitude: Double,
        longitude: Double,
        range: ClosedRange<Date>
    ) async throws -> EnvironmentalTimeSeries {
        guard latitude >= -90, latitude <= 90, longitude >= -180, longitude <= 180 else {
            throw EnvironmentalDataError.invalidLocation
        }

        async let air = fetchAirQuality(latitude: latitude, longitude: longitude)
        async let weather = fetchWeather(latitude: latitude, longitude: longitude)

        let airResult = try await air
        let weatherResult = try await weather

        var merged: [Date: EnvironmentalSample] = [:]
        for (date, values) in airResult.values {
            merged[date] = EnvironmentalSample(
                timestamp: date,
                pm25: values.pm25,
                ozone: values.ozone
            )
        }
        for (date, values) in weatherResult.values {
            var sample = merged[date] ?? EnvironmentalSample(timestamp: date)
            sample.temperatureC = values.temperature
            sample.apparentTemperatureC = values.apparentTemperature
            sample.relativeHumidity = values.humidity
            sample.uvIndex = values.uvIndex
            sample.precipitationProbability = values.precipitationProbability
            merged[date] = sample
        }

        let samples = merged.values.sorted { $0.timestamp < $1.timestamp }
        guard !samples.isEmpty else { throw EnvironmentalDataError.forecastUnavailable }

        let series = EnvironmentalTimeSeries(
            samples: samples,
            source: Self.sourceName,
            kind: .forecast,
            fetchedAt: Date(),
            timeZoneIdentifier: airResult.timeZone,
            intervalSemantics: "Each hourly value is treated as the mean for the hour beginning at its timestamp.",
            attributionURL: Self.attribution
        )

        guard let covered = series.coveredRange,
              covered.contains(range.lowerBound), covered.contains(range.upperBound) else {
            throw EnvironmentalDataError.outsideForecastRange
        }
        return series
    }

    // MARK: - Air quality

    private struct AirValues { var pm25: Double?; var ozone: Double? }

    private func fetchAirQuality(latitude: Double, longitude: Double) async throws
        -> (values: [Date: AirValues], timeZone: String)
    {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "hourly", value: "pm2_5,ozone"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "3"),
            .init(name: "past_days", value: "1")
        ]
        let json = try await getJSON(components.url)
        guard let hourly = json["hourly"] as? [String: Any],
              let times = hourly["time"] as? [String],
              let timeZoneID = json["timezone"] as? String
        else { throw EnvironmentalDataError.malformedResponse }

        let pm25 = hourly["pm2_5"] as? [Double?] ?? []
        let ozone = hourly["ozone"] as? [Double?] ?? []
        let formatter = Self.makeFormatter(timeZoneID: timeZoneID)

        var out: [Date: AirValues] = [:]
        for (index, raw) in times.enumerated() {
            guard let date = formatter.date(from: raw) else { continue }
            out[date] = AirValues(
                pm25: index < pm25.count ? pm25[index] : nil,
                ozone: index < ozone.count ? ozone[index] : nil
            )
        }
        guard !out.isEmpty else { throw EnvironmentalDataError.forecastUnavailable }
        return (out, timeZoneID)
    }

    // MARK: - Weather

    private struct WeatherValues {
        var temperature: Double?
        var apparentTemperature: Double?
        var humidity: Double?
        var uvIndex: Double?
        var precipitationProbability: Double?
    }

    private func fetchWeather(latitude: Double, longitude: Double) async throws
        -> (values: [Date: WeatherValues], timeZone: String)
    {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "hourly", value: "temperature_2m,apparent_temperature,relative_humidity_2m,uv_index,precipitation_probability"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "3"),
            .init(name: "past_days", value: "1")
        ]
        let json = try await getJSON(components.url)
        guard let hourly = json["hourly"] as? [String: Any],
              let times = hourly["time"] as? [String],
              let timeZoneID = json["timezone"] as? String
        else { throw EnvironmentalDataError.malformedResponse }

        let temperature = hourly["temperature_2m"] as? [Double?] ?? []
        let apparent = hourly["apparent_temperature"] as? [Double?] ?? []
        let humidity = hourly["relative_humidity_2m"] as? [Double?] ?? []
        let uvIndex = hourly["uv_index"] as? [Double?] ?? []
        let precipitation = hourly["precipitation_probability"] as? [Double?] ?? []
        let formatter = Self.makeFormatter(timeZoneID: timeZoneID)

        var out: [Date: WeatherValues] = [:]
        for (index, raw) in times.enumerated() {
            guard let date = formatter.date(from: raw) else { continue }
            out[date] = WeatherValues(
                temperature: index < temperature.count ? temperature[index] : nil,
                apparentTemperature: index < apparent.count ? apparent[index] : nil,
                humidity: index < humidity.count ? humidity[index] : nil,
                uvIndex: index < uvIndex.count ? uvIndex[index] : nil,
                precipitationProbability: index < precipitation.count ? precipitation[index] : nil
            )
        }
        return (out, timeZoneID)
    }

    // MARK: - Plumbing

    /// Open-Meteo returns local wall-clock strings ("2026-09-19T18:00") in the
    /// location's own time zone. We parse them against that zone rather than
    /// the device zone.
    private static func makeFormatter(timeZoneID: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }

    private func getJSON(_ url: URL?) async throws -> [String: Any] {
        guard let url else { throw EnvironmentalDataError.invalidLocation }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 { throw EnvironmentalDataError.rateLimited }
                guard (200..<300).contains(http.statusCode) else {
                    throw EnvironmentalDataError.network(underlying: "HTTP \(http.statusCode)")
                }
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EnvironmentalDataError.malformedResponse
            }
            if json["error"] != nil { throw EnvironmentalDataError.malformedResponse }
            return json
        } catch let error as EnvironmentalDataError {
            throw error
        } catch let error as URLError {
            throw error.code == .timedOut
                ? EnvironmentalDataError.timedOut
                : EnvironmentalDataError.network(underlying: error.localizedDescription)
        } catch {
            throw EnvironmentalDataError.malformedResponse
        }
    }
}
