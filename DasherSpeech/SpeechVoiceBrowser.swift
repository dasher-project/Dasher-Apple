import SwiftUI

struct SpeechVoiceBrowser: View {
    let service: SpeechService
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var filters = VoiceFilters()

    private var results: [SpeechVoice] {
        service.availableVoices.filter { voice in
            filters.matches(voice.metadata, search: search, terms: [voice.name, voice.id])
        }
    }

    var body: some View {
        let results = results
        NavigationStack {
            List {
                if service.isLoadingVoices {
                    ProgressView("Loading voices…")
                } else if service.availableVoices.isEmpty {
                    ContentUnavailableView("No voices available", systemImage: "speaker.slash",
                                           description: service.errorMessage.map { Text($0) })
                    Button("Load Voices") { service.loadVoices() }
                } else {
                    if !filters.isActive && search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { select(nil) } label: {
                            VoiceBrowserRow(title: String(localized: "Default Voice"), subtitle: "", selected: service.selectedVoice == nil)
                        }
                    }
                    if results.isEmpty {
                        ContentUnavailableView("No matching voices", systemImage: "magnifyingglass")
                    } else {
                        ForEach(results) { voice in
                            Button { select(voice.id) } label: {
                                VoiceBrowserRow(title: voice.name, subtitle: voice.metadata.subtitle,
                                                selected: voice.id == service.selectedVoice)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .searchable(text: $search, prompt: "Search voices")
            .navigationTitle(service.isSherpa ? "Model Speakers" : "Voices")
            .safeAreaInset(edge: .top, spacing: 0) {
                if !service.availableVoices.isEmpty {
                    VoiceFilterBar(filters: $filters, metadata: service.availableVoices.map(\.metadata),
                                   resultCount: results.count)
                }
            }
            .toolbar {
                if !service.availableVoices.isEmpty {
                    ToolbarItem {
                        Button {
                            service.loadVoices()
                        } label: {
                            Label("Reload Voices", systemImage: "arrow.clockwise")
                        }
                        .disabled(service.isLoadingVoices)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 480)
        #endif
    }

    private func select(_ id: String?) {
        service.selectedVoice = id
        dismiss()
    }
}

struct VoiceBrowserRow: View {
    let title: String
    let subtitle: String
    var selected = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct VoiceFilterBar: View {
    @Binding var filters: VoiceFilters
    let metadata: [VoiceMetadata]
    let resultCount: Int
    @State private var showsFilters = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button { showsFilters = true } label: {
                    Label("Filters", systemImage: filters.isActive
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                Spacer()
                Group {
                    if resultCount == 1 {
                        Text("1 result")
                    } else {
                        Text("\(resultCount.formatted()) results")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if filters.isActive {
                    Button("Clear Filters") { filters = VoiceFilters() }
                }
            }
            if filters.isActive {
                Text([filters.language, filters.gender?.title, filters.type].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .sheet(isPresented: $showsFilters) {
            VoiceFilterSettings(filters: $filters, metadata: metadata)
        }
    }
}

private struct VoiceFilterSettings: View {
    @Binding var filters: VoiceFilters
    let metadata: [VoiceMetadata]
    @Environment(\.dismiss) private var dismiss

    private var languages: [String] {
        sorted(Set(metadata.flatMap { $0.languages.map(\.filterName) }))
    }

    var body: some View {
        NavigationStack {
            Form {
                NavigationLink {
                    VoiceLanguageFilter(language: $filters.language, languages: languages)
                } label: {
                    LabeledContent("Language", value: filters.language ?? String(localized: "Any"))
                }
                .disabled(languages.isEmpty)

                Picker("Gender", selection: $filters.gender) {
                    Text("Any").tag(nil as VoiceGender?)
                    ForEach(VoiceGender.allCases.filter { gender in metadata.contains { $0.gender == gender } },
                            id: \.self) { gender in
                        Text(gender.title).tag(gender as VoiceGender?)
                    }
                }

                if !metadata.compactMap(\.type).isEmpty {
                    Picker("Voice Type", selection: $filters.type) {
                        Text("Any").tag(nil as String?)
                        ForEach(sorted(Set(metadata.compactMap(\.type))), id: \.self) { type in
                            Text(type).tag(type as String?)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Voice Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }

    private func sorted(_ values: Set<String>) -> [String] {
        values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

private struct VoiceLanguageFilter: View {
    @Binding var language: String?
    let languages: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        List {
            if search.isEmpty { choice(nil) }
            ForEach(languages.filter { search.isEmpty || $0.localizedStandardContains(search) }, id: \.self) { name in
                choice(name)
            }
        }
        .buttonStyle(.plain)
        .searchable(text: $search, prompt: "Find a language")
        .navigationTitle("Language")
    }

    private func choice(_ name: String?) -> some View {
        Button {
            language = name
            dismiss()
        } label: {
            VoiceBrowserRow(title: name ?? String(localized: "Any Language"), subtitle: "", selected: language == name)
        }
    }
}
