import SwiftUI

@main
struct ExposureNavigatorApp: App {
    @State private var app = AppState()
    var body: some Scene {
        WindowGroup {
            Group {
                if app.onboardingComplete { MainTabView() }
                else { OnboardingView() }
            }
            .environment(app)
            .tint(ResilioTheme.tint)
            .alert("Couldn't save your changes", isPresented: Binding(
                get: { app.profiles.storageError != nil || app.events.storageError != nil },
                set: { if !$0 { app.profiles.storageError = nil; app.events.storageError = nil } }
            )) { Button("OK", role: .cancel) {} } message: {
                Text(app.profiles.storageError ?? app.events.storageError ?? "Please try again.")
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            HomeView().tabItem { Label("Home", systemImage: "house") }.tag(AppState.Tab.home)
            PlanBuilderView().tabItem { Label("Schedule", systemImage: "calendar.badge.plus") }.tag(AppState.Tab.schedule)
            CalendarView().tabItem { Label("Calendar", systemImage: "calendar") }.tag(AppState.Tab.calendar)
            ProfilesView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(AppState.Tab.profile)
        }
    }
}
