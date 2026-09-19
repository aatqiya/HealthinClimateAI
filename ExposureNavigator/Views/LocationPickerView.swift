import SwiftUI

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = AddressSearchService()
    @State private var query = ""
    @State private var matches: [ActivityLocation] = []
    @State private var resolving = false
    @State private var error: String?
    let onSelect: (ActivityLocation) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("City, address, or place", text: $query).textContentType(.fullStreetAddress)
                        .onChange(of: query) { _, value in matches = []; search.search(value) }
                    Button("Search") { Task { await findPlaces() } }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || resolving)
                    ForEach(matches, id: \.self) { location in
                        Button { onSelect(location); dismiss() } label: { VStack(alignment: .leading) { Text(location.name); Text(location.formattedAddress).font(.caption).foregroundStyle(.secondary) } }
                    }
                    ForEach(search.suggestions) { suggestion in
                        Button {
                            Task { await resolve(suggestion) }
                        } label: {
                            VStack(alignment: .leading) { Text(suggestion.title); Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary) }
                        }.disabled(resolving)
                    }
                } footer: { Text("Choose a search result to confirm the location. Your home location and event addresses can be different.") }
                if resolving { ProgressView("Finding location…") }
                if let error { Text(error).foregroundStyle(.secondary) }
            }
            .navigationTitle("Choose a location").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }.tint(ResilioTheme.tint)
    }
    func findPlaces() async {
        let requested = query
        resolving = true; defer { resolving = false }
        do { let found = try await search.lookup(requested); guard requested == query else { return }; matches = found; error = nil }
        catch { self.error = "No matching places. Try a more complete address." }
    }
    func resolve(_ suggestion: LocationSuggestion) async {
        resolving = true; defer { resolving = false }
        do { let location = try await search.resolve(suggestion); onSelect(location); dismiss() }
        catch { self.error = "Couldn't find that location. Please try another result." }
    }
}
