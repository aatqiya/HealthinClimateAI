import SwiftUI

struct TagInput: View {
    let title: String
    let suggestions: [String]
    @Binding var values: [String]
    @State private var text = ""
    var query: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var filtered: [String] {
        guard !query.isEmpty, values.count < 25 else { return [] }
        return Array(suggestions.filter { candidate in
            candidate.localizedCaseInsensitiveContains(query) && !values.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }.prefix(5))
    }
    var body: some View {
        Section {
            if !values.isEmpty {
                FlowLayout {
                    ForEach(values, id: \.self) { value in
                        HStack {
                            Text(value).font(.subheadline)
                            Spacer(minLength: 2)
                            Button { values.removeAll { $0 == value } } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 32, minHeight: 44) }
                                .buttonStyle(.borderless).accessibilityLabel("Remove \(value)")
                        }.padding(.horizontal, 10).background(ResilioTheme.sage.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            if values.count < 25 {
                HStack {
                    TextField("Start typing…", text: $text).onSubmit { add(query) }.submitLabel(.done)
                    Button("Add") { add(query) }.disabled(query.isEmpty).buttonStyle(.borderless)
                }
                ForEach(filtered, id: \.self) { suggestion in Button(suggestion) { add(suggestion) } }
            }
            Text("\(values.count) of 25 entries").font(.caption).foregroundStyle(.secondary)
        } header: { Text(title) } footer: { Text("Optional. Only information you choose to add is used to personalize your experience.") }
    }
    func add(_ value: String) {
        values = ProfileTags.adding(value, to: values)
        text = ""
    }
}
struct FlowLayout<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading, spacing: 8) { content } }
}
