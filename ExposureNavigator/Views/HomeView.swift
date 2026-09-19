import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("temperatureUnit") private var unit = "fahrenheit"
    @State private var showingProfiles = false
    @State private var showingAI = false
    @State private var choosingLocation = false
    @State private var resolvedZIP: (String, ActivityLocation)?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(greeting).font(.system(.title, design: .rounded, weight: .bold))
                            Button { showingProfiles = true } label: {
                                HStack { Text("Planning for \(app.profiles.selectedProfile?.name ?? "someone new")"); Image(systemName: "chevron.down").font(.caption.bold()) }
                            }.font(.subheadline).frame(minHeight: 44)
                        }
                        Spacer(minLength: 4)
                        Image("ResilioLogo").resizable().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 17)).accessibilityHidden(true)
                    }
                    conditions
                    hourly
                    Button { showingAI = true } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "sparkles").font(.title)
                            VStack(alignment: .leading, spacing: 5) { Text("Plan with AI").font(.headline); Text("Start with what's on your mind.").font(.subheadline).opacity(0.85) }
                            Spacer(); Image(systemName: "arrow.up.right")
                        }.padding(22).foregroundStyle(.white).background(ResilioTheme.forest, in: RoundedRectangle(cornerRadius: 24))
                    }.buttonStyle(.plain)
                    upcoming
                }.padding(20)
            }.background(ResilioTheme.background).refreshable { await refresh() }
                .navigationTitle("Resilio").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingProfiles) { ProfileSwitcher() }
                .sheet(isPresented: $showingAI) { AIPlannerView() }
                .sheet(isPresented: $choosingLocation) { LocationPickerView { app.manualLocation = $0 } }
                .task(id: refreshIdentity) { await refresh() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    app.location.requestIfAuthorized()
                    while !Task.isCancelled {
                        if app.selectedTab == .home { await refresh() }
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    }
                }
        }
    }
    var refreshIdentity: String { "\(app.profiles.selectedProfileID?.uuidString ?? "")-\(app.manualLocation?.latitude ?? 0)-\(app.manualLocation?.longitude ?? 0)-\(app.location.location?.coordinate.latitude ?? 0)-\(app.location.location?.coordinate.longitude ?? 0)" }
    var greeting: String { let hour = Calendar.current.component(.hour, from: Date()); return hour < 12 ? "Good morning." : (hour < 17 ? "Good afternoon." : "Good evening.") }
    var currentSample: EnvironmentalSample? { app.environment.current?.series.samples.first { $0.timestamp <= Date() && $0.timestamp.addingTimeInterval(3600) > Date() } }
    @ViewBuilder var conditions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Around you").font(.title2.bold()); Spacer()
                if app.environment.isLoading { ProgressView() }
                else { Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Refresh conditions") }
            }
            Button { choosingLocation = true } label: { Label(app.environment.current?.location.name ?? app.manualLocation?.name ?? "Choose a location", systemImage: "location").font(.subheadline) }
            if let sample = currentSample {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ConditionCard(title: "Temperature", value: DisplayFormat.temperature(sample.temperatureC, unit: unit), detail: "Hourly forecast", icon: "thermometer.medium")
                    ConditionCard(title: "Air quality", value: DisplayFormat.airQuality(sample.usAQI), detail: sample.usAQI.map { "US AQI · \(Int($0.rounded()))" } ?? "No reading available", icon: "aqi.medium")
                    ConditionCard(title: "UV", value: uvLabel(sample.uvIndex), detail: sample.uvIndex.map { "Index · \(String(format: "%.1f", $0))" } ?? "No reading available", icon: "sun.max")
                    ConditionCard(title: "Feels like", value: DisplayFormat.temperature(sample.apparentTemperatureC, unit: unit), detail: "Heat & humidity", icon: "sun.haze")
                }
                if let cached = app.environment.current {
                    DisclosureGroup("Forecast details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sample.pm25.map { "Fine particle pollution (PM2.5): \(Int($0.rounded())) µg/m³" } ?? "Fine particle pollution unavailable")
                            Text("App checked: \((app.environment.lastCheckedAt ?? cached.checkedAt).formatted(date: .omitted, time: .shortened))")
                            Text("Forecast retrieved: \(cached.series.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            Text("Source update time is not supplied. These are hourly forecasts, not live sensor readings.")
                            Link("Open-Meteo · CAMS air quality & weather", destination: URL(string: "https://open-meteo.com/en/docs/air-quality-api")!)
                        }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    }.font(.caption)
                }
            } else if app.environment.isLoading { Text("Looking up your forecast…").foregroundStyle(.secondary) }
            else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A little local context.").font(.headline)
                    Text("Choose a city or address to see air quality and heat around your plans.").foregroundStyle(.secondary)
                    Button("Add a location") { choosingLocation = true }
                    Button("Use current location") { app.manualLocation = nil; app.location.request() }
                }.resilioCard()
            }
            if let error = app.environment.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
    }
    var hourly: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The next few hours").font(.title2.bold())
            let samples = app.environment.current?.series.samples.filter { $0.timestamp.addingTimeInterval(3600) > Date() }.prefix(12) ?? []
            if samples.isEmpty { Text("Your hourly forecast will appear here.").font(.subheadline).foregroundStyle(.secondary) }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(samples), id: \.timestamp) { sample in
                            VStack(spacing: 10) {
                                Text(app.environment.current.map { DisplayFormat.time(sample.timestamp, at: $0.location) } ?? sample.timestamp.formatted(date: .omitted, time: .shortened)).font(.caption)
                                Image(systemName: sample.usAQI.map { $0 > 100 ? "aqi.medium" : "leaf" } ?? "clock").font(.title3).foregroundStyle(ResilioTheme.tint)
                                Text(DisplayFormat.temperature(sample.temperatureC, unit: unit)).font(.headline)
                                Text(DisplayFormat.airQuality(sample.usAQI)).font(.caption2).multilineTextAlignment(.center)
                                if let rain = sample.precipitationProbability { Text("\(Int(rain.rounded()))% rain").font(.caption2).foregroundStyle(.secondary) }
                            }.frame(width: 94, alignment: .top).padding(.vertical, 16)
                                .background(ResilioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
            }
        }
    }
    var upcoming: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Upcoming plans").font(.title2.bold()); Spacer(); Button("See all") { app.selectedTab = .calendar }.font(.subheadline) }
            if app.events.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "calendar.badge.plus").font(.title).foregroundStyle(ResilioTheme.tint)
                    Text("Make room for a better plan.").font(.headline)
                    Text("Add something you need to do. We'll help you explore the timing.").foregroundStyle(.secondary)
                    Button("Schedule a plan") { app.selectedTab = app.profiles.selectedProfile == nil ? .profile : .schedule }.frame(minHeight: 44)
                }.resilioCard()
            } else {
                ForEach(app.events.upcoming.prefix(5)) { event in
                    Button { app.openEvent(event) } label: { EventRow(event: event, profile: app.profiles.profiles.first { $0.id == event.profileID }).resilioCard() }.buttonStyle(.plain)
                }
            }
        }
    }
    func refresh() async {
        if let manual = app.manualLocation { await app.environment.refresh(location: manual); return }
        if let location = app.location.location {
            await app.environment.refresh(location: .init(name: app.location.placeName, formattedAddress: app.location.placeName, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)); return
        }
        if let zip = app.profiles.selectedProfile?.homeZipCode {
            if resolvedZIP?.0 != zip, let location = try? await AddressSearchService().resolveAddress(zip) { resolvedZIP = (zip, location) }
            if let match = resolvedZIP, match.0 == zip { await app.environment.refresh(location: match.1) }
        } else {
            app.environment.current = nil; app.environment.errorMessage = nil
        }
    }
    func uvLabel(_ value: Double?) -> String { guard let value else { return "Unavailable" }; return value < 3 ? "Low" : (value < 6 ? "Moderate" : (value < 8 ? "High" : (value < 11 ? "Very high" : "Extreme"))) }
}

struct ConditionCard: View {
    let title, value, detail, icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(ResilioTheme.tint)
            Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).minimumScaleFactor(0.75)
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 128, alignment: .leading).padding(16)
            .background(ResilioTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
struct EventRow: View {
    let event: ActivityEvent
    let profile: UserProfile?
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar").font(.title2).foregroundStyle(ResilioTheme.tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(event.plan.activityName).font(.headline)
                Text(profile?.name ?? "Deleted profile").font(.subheadline).foregroundStyle(ResilioTheme.tint)
                Text(DisplayFormat.date(event.selectedStart, at: event.plan.location) + " · " + DisplayFormat.time(event.selectedStart, at: event.plan.location)).font(.subheadline)
                Text(event.plan.location.name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4).contentShape(Rectangle())
    }
}
