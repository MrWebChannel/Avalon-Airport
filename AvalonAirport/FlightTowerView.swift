import SwiftUI
import AvalonCore
#if os(iOS)
import UIKit
import UniformTypeIdentifiers
#endif

/// Governance for the journey, on the active controller's device: delay rules, the clock,
/// and the journey file itself (read it, append updates to it, share it).
struct FlightTowerView: View {
    @Environment(JourneyStore.self) private var store
    private let fallback: JourneySnapshot
    /// Read live from the store so this screen reflects changes made on it.
    private var snapshot: JourneySnapshot { store.snapshot ?? fallback }

    init(snapshot: JourneySnapshot) {
        fallback = snapshot
    }

    private static let graceOptions: [Double] = [0, 6, 12, 24, 48]
    private static let staleOptions: [Int] = [1, 3, 7, 14, 30]

    var body: some View {
        List {
            if let tower = store.tower {
                Section {
                    LabeledContent("Tower", value: tower.id)
                    LabeledContent("Active controller", value: snapshot.passenger(tower.activeControllerId)?.name ?? "None")
                    LabeledContent("Controllers", value: tower.controllerIds
                        .map { snapshot.passenger($0)?.name ?? $0 }.joined(separator: ", "))
                } header: {
                    Text("Control")
                } footer: {
                    Text("This device is the one writer for the journey. The tower stays here and is never sent in a package.")
                }

                Section("Delay rules") {
                    Picker("Grace after ETA", selection: Binding(
                        get: { tower.delayRules.graceHours },
                        set: { store.setDelayRules(DelayRules(graceHours: $0, staleContactDays: tower.delayRules.staleContactDays)) }
                    )) {
                        ForEach(Self.graceOptions, id: \.self) { hours in
                            Text(hours == 0 ? "None" : "\(Int(hours)) hours").tag(hours)
                        }
                    }
                    Picker("No contact after", selection: Binding(
                        get: { tower.delayRules.staleContactDays },
                        set: { store.setDelayRules(DelayRules(graceHours: tower.delayRules.graceHours, staleContactDays: $0)) }
                    )) {
                        ForEach(Self.staleOptions, id: \.self) { days in
                            Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                        }
                    }
                }
            }

            Section {
                LabeledContent("Tower clock") {
                    Text(store.now, format: .dateTime.month(.abbreviated).day().hour().minute())
                }
                Button("Advance 1 day") { store.advanceClock(days: 1) }
                Button("Advance 1 week") { store.advanceClock(days: 7) }
                if store.clockOffsetDays != 0 {
                    Button("Back to real time") { store.resetClock() }
                }
            } header: {
                Text("Clock")
            } footer: {
                Text("Simulate time to watch flights flip to delayed. Delays already logged stay in the log.")
            }

            Section {
                NavigationLink {
                    YAMLReaderView(source: .journey)
                } label: {
                    Label("Read journey YAML", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink {
                    AppendYAMLView()
                } label: {
                    Label("Append YAML", systemImage: "text.badge.plus")
                }
                NavigationLink {
                    YAMLReaderView(source: .tower)
                } label: {
                    Label("Read tower YAML", systemImage: "lock.doc")
                }
                #if os(iOS)
                ShareLink(item: JourneyStore.journeyFile) {
                    Label("Share journey.avj", systemImage: "square.and.arrow.up")
                }
                #endif
            } header: {
                Text("Journey file")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(snapshot.events.count) events · last hash \(snapshot.events.last?.eventHash.map { String($0.prefix(12)) } ?? "none")")
                    if let error = store.saveError {
                        Text(error).foregroundStyle(Theme.delayed)
                    }
                }
            }

            Section {
                Button("Reset to sample journey", role: .destructive) { store.loadSample() }
            } footer: {
                Text("Discards this device's journey and starts again from anti-hustle.avj.")
            }
        }
        .navigationTitle("Flight Tower")
    }
}

// MARK: - Reading YAML

struct YAMLReaderView: View {
    enum Source {
        case journey, tower

        var title: String { self == .journey ? "journey.avj" : "tower.yaml" }
    }

    @Environment(JourneyStore.self) private var store
    let source: Source

    private var text: String {
        do {
            return try source == .journey ? store.exportYAML() : store.towerYAML()
        } catch {
            return "# Could not encode: \(error.localizedDescription)"
        }
    }

    var body: some View {
        let text = self.text
        ScrollView {
            #if os(tvOS)
            // The Siri Remote scrolls by moving focus, so the file is split into focusable blocks.
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.blocks(of: text).enumerated()), id: \.offset) { _, block in
                    Text(block)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusable()
                }
            }
            .padding()
            #else
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            #endif
        }
        .navigationTitle(source.title)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
        #endif
    }

    private static func blocks(of text: String, linesPerBlock: Int = 12) -> [String] {
        let lines = text.components(separatedBy: "\n")
        return stride(from: 0, to: lines.count, by: linesPerBlock).map {
            lines[$0..<min($0 + linesPerBlock, lines.count)].joined(separator: "\n")
        }
    }
}

// MARK: - Appending YAML

/// Paste or write an update (an `.avj` update package, or a bare `update:` document) and append it.
/// The delay rules decide whether it is accepted; nothing already in the journey is overwritten.
struct AppendYAMLView: View {
    @Environment(JourneyStore.self) private var store
    @State private var text = ""
    @State private var templateFlightId = ""
    @State private var outcome: Outcome?
    #if os(iOS)
    @State private var importing = false
    #endif

    private enum Outcome {
        case appended([Event])
        case rejected(String)
    }

    var body: some View {
        Form {
            Section {
                Picker("Template for", selection: $templateFlightId) {
                    ForEach(store.snapshot?.orderedFlights ?? []) { flight in
                        Text("\(flight.code) · \(flight.title)").tag(flight.id)
                    }
                }
                #if os(iOS)
                Button {
                    importing = true
                } label: {
                    Label("Open .avj or YAML file", systemImage: "folder")
                }
                #endif
            } footer: {
                Text("Start from a template, or paste an update package received from an airline.")
            }

            Section("YAML") {
                #if os(tvOS)
                TextField("journeyPackage: …", text: $text, axis: .vertical)
                    .font(.system(.caption, design: .monospaced))
                #else
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 320)
                #endif
            }

            Section {
                Button("Append to journey") { append() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let outcome {
                Section("Result") {
                    switch outcome {
                    case .appended(let events):
                        Label(events.isEmpty ? "Appended. Message only, no status change."
                                             : "Appended. \(events.count) new events.",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.onTime)
                        ForEach(events) { event in
                            Text("\(event.id) \(event.type.rawValue)")
                                .font(.caption.monospaced())
                        }
                    case .rejected(let message):
                        Label(message, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(Theme.delayed)
                    }
                }
            }
        }
        .navigationTitle("Append YAML")
        .onAppear {
            if templateFlightId.isEmpty {
                templateFlightId = store.snapshot?.orderedFlights.first?.id ?? ""
                text = store.updateTemplate(for: templateFlightId)
            }
        }
        .onChange(of: templateFlightId) {
            text = store.updateTemplate(for: templateFlightId)
            outcome = nil
        }
        #if os(iOS)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: AVJ.fileExtension) ?? .data, .yaml, .plainText]) { result in
            readImported(result)
        }
        #endif
    }

    private func append() {
        do {
            outcome = .appended(try store.appendYAML(text))
        } catch {
            outcome = .rejected(error.localizedDescription)
        }
    }

    #if os(iOS)
    private func readImported(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            text = try String(contentsOf: url, encoding: .utf8)
            outcome = nil
        } catch {
            outcome = .rejected("Could not open the file: \(error.localizedDescription)")
        }
    }
    #endif
}
