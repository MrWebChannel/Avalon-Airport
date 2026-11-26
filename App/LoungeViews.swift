import SwiftUI
import AvalonCore

// MARK: - Lounge: private chat between people you add, carried by Jet-Stream

/// Private to the people you add. Airlines and their agents never receive Lounge messages.
/// While this tab is open it checks Jet-Stream every few seconds; elsewhere the app checks once a minute.
struct LoungeView: View {
    @Environment(AppModel.self) private var model
    @Environment(JetStream.self) private var jet

    var body: some View {
        Group {
            if jet.isSignedIn {
                LoungeChatView()
            } else {
                LoungeSetUpPrompt()
            }
        }
        .navigationTitle("Lounge")
    }
}

struct LoungeChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(JetStream.self) private var jet
    @State private var draft = ""
    @State private var showingPeople = false
    @State private var sending = false

    /// The sender's journey names the thread; with no journey it is the general Lounge.
    private var thread: String { model.journey?.id ?? "lounge" }
    private var threadTitle: String { model.journey?.title ?? "Lounge" }
    private var showThreadLabels: Bool { Set(jet.messages.map(\.thread)).count > 1 }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Text("Private to the people you add. Airlines and their agents never see the Lounge.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if jet.contacts.isEmpty {
                        Button { showingPeople = true } label: {
                            Label("Add someone by email to start", systemImage: "person.badge.plus")
                        }
                    } else {
                        Text("Sending to " + jet.contacts.map(\.name).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Conversation") {
                    if jet.messages.isEmpty { Text("No messages yet").foregroundStyle(.secondary) }
                    ForEach(jet.messages) { message in
                        LoungeBubble(message: message, showThread: showThreadLabels).id(message.id)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .onChange(of: jet.messages.count) {
                if let last = jet.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let text = draft
                    draft = ""
                    sending = true
                    Task {
                        await jet.sendLounge(text, thread: thread, threadTitle: threadTitle)
                        sending = false
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingPeople = true } label: { Label("People", systemImage: "person.2") }
            }
            ToolbarItem(placement: .topBarLeading) {
                if let last = jet.lastCheck {
                    Text(last, format: .dateTime.hour().minute().second())
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingPeople) { LoungePeopleView() }
        // Errors show here only while the People sheet is closed; the sheet shows its own.
        .alert("Lounge", isPresented: Binding(get: { jet.errorMessage != nil && !showingPeople },
                                              set: { if !$0 { jet.errorMessage = nil } })) {
            Button("OK") { jet.errorMessage = nil }
        } message: { Text(jet.errorMessage ?? "") }
        // Fast check while the Lounge is on screen. SwiftUI cancels this task when the tab is left.
        .task {
            jet.unread = 0
            while !Task.isCancelled {
                await jet.check()
                jet.unread = 0
                try? await Task.sleep(for: .seconds(JetStreamConfig.loungeCheckSeconds))
            }
        }
    }
}

struct LoungeBubble: View {
    let message: LoungeChatMessage
    let showThread: Bool

    var body: some View {
        HStack {
            if message.mine { Spacer(minLength: 40) }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !message.mine { Text(message.fromName).font(.caption.bold()) }
                    if showThread, let title = message.threadTitle {
                        Text(title).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(message.mine ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.25),
                                in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 4) {
                    Text(message.at, format: .dateTime.month().day().hour().minute())
                    if message.mine { Text(deliveryText) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            if !message.mine { Spacer(minLength: 40) }
        }
    }

    private var deliveryText: String {
        let total = message.rowIds.count
        guard total > 0 else { return "" }
        if message.deliveredCount == 0 { return "· sent" }
        if message.deliveredCount == total { return "· delivered" }
        return "· delivered \(message.deliveredCount)/\(total)"
    }
}

/// Who receives your Lounge messages. You add people by their exact email; people who message you
/// are added automatically so you can reply.
struct LoungePeopleView: View {
    @Environment(JetStream.self) private var jet
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section("Add by email or @username") {
                    TextField("their@email.com or @username", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    Button(adding ? "Looking up..." : "Add to Lounge") {
                        adding = true
                        Task {
                            await jet.addContact(email: email)
                            if jet.errorMessage == nil { email = "" }
                            adding = false
                        }
                    }
                    .disabled(adding || email.trimmingCharacters(in: .whitespaces).count < 3)
                }
                Section("In your Lounge") {
                    if jet.contacts.isEmpty { Text("Nobody yet").foregroundStyle(.secondary) }
                    ForEach(jet.contacts) { c in
                        VStack(alignment: .leading) {
                            Text(c.name)
                            if let e = c.email { Text(e).font(.caption).foregroundStyle(.secondary) }
                        }
                        .swipeActions { Button("Remove", role: .destructive) { jet.removeContact(c) } }
                    }
                }
                Section("You") {
                    HStack(spacing: 12) {
                        ProfileAvatar(data: jet.profilePhoto, size: 44)
                        VStack(alignment: .leading) {
                            Text(jet.myName).bold()
                            if let handle = jet.myUsername { Text("@\(handle)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    LabeledContent("Email", value: jet.session?.email ?? "")
                    Button("Sign out of Jet-Stream", role: .destructive) { jet.signOut(); dismiss() }
                }
                if let notice = jet.noticeMessage {
                    Section { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Lounge people")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Lounge", isPresented: Binding(get: { jet.errorMessage != nil }, set: { if !$0 { jet.errorMessage = nil } })) {
                Button("OK") { jet.errorMessage = nil }
            } message: { Text(jet.errorMessage ?? "") }
        }
    }
}

/// Shown in the Lounge until this device has an account. Opens the same setup as first launch.
struct LoungeSetUpPrompt: View {
    @State private var showingSetup = false

    var body: some View {
        ContentUnavailableView {
            Label("Set up your account", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("The Lounge carries private messages between Avalon apps. Set up once on this device.")
        } actions: {
            Button("Set up") { showingSetup = true }
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showingSetup) { OnboardingView() }
    }
}
