import SwiftUI
import PhotosUI
import UIKit

/// First-run setup: name, username, email, password and an optional photo.
/// Creates the Jet-Stream account the Lounge (and later flight updates) use.
/// The photo stays on this device; Avalon never sends images through Jet-Stream.
struct OnboardingView: View {
    @Environment(JetStream.self) private var jet
    @Environment(\.dismiss) private var dismiss
    /// Shown as "Not now" on first launch. When nil (opened from the Lounge) the button reads "Close".
    var onSkip: (() -> Void)? = nil

    enum Mode { case create, signIn }
    enum UsernameState { case empty, invalid, checking, available, taken, unknown }

    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var usernameState: UsernameState = .empty
    @State private var working = false

    private var emailOK: Bool { email.contains("@") && email.contains(".") }
    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && emailOK && password.count >= 8 && password == confirm
            && (usernameState == .available || usernameState == .unknown)
    }
    private var canSignIn: Bool { emailOK && password.count >= 6 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Text("Welcome to Avalon Airport")
                            .font(.title2.bold())
                        Text("The client owns the airport. Set up who you are, then invite the people on your journey.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Picker("", selection: $mode) {
                            Text("New here").tag(Mode.create)
                            Text("I have an account").tag(Mode.signIn)
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                if mode == .create {
                    createSections
                } else {
                    signInSections
                }

                if let notice = jet.noticeMessage {
                    Section { Text(notice).font(.footnote) }
                }
            }
            .navigationTitle("Set up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(onSkip == nil ? "Close" : "Not now") {
                        if let onSkip { onSkip() } else { dismiss() }
                    }
                }
            }
            .alert("Avalon", isPresented: Binding(get: { jet.errorMessage != nil }, set: { if !$0 { jet.errorMessage = nil } })) {
                Button("OK") { jet.errorMessage = nil }
            } message: { Text(jet.errorMessage ?? "") }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        photoData = image.avatarJPEG(maxSide: 512)
                    }
                }
            }
            // Checks the username half a second after typing stops.
            .task(id: username) {
                let handle = JetStream.normalizedUsername(username)
                guard !handle.isEmpty else { usernameState = .empty; return }
                guard JetStream.isValidUsername(handle) else { usernameState = .invalid; return }
                usernameState = .checking
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                switch await jet.usernameAvailable(handle) {
                case .some(true): usernameState = .available
                case .some(false): usernameState = .taken
                case .none: usernameState = .unknown
                }
            }
        }
    }

    // MARK: New account

    @ViewBuilder private var createSections: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ProfileAvatar(data: photoData, size: 104, placeholder: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.plain)
                    Text(photoData == nil ? "Add a photo (optional)" : "Tap to change")
                        .font(.caption).foregroundStyle(.secondary)
                    if photoData != nil {
                        Button("Remove photo", role: .destructive) { photoData = nil; photoItem = nil }
                            .font(.caption)
                    }
                }
                Spacer()
            }
        } footer: {
            Text("Your photo stays on this device.")
        }

        Section {
            TextField("Your name", text: $name)
                .textContentType(.name)
            HStack {
                Text("@").foregroundStyle(.secondary)
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.nickname)
                usernameBadge
            }
        } header: {
            Text("You")
        } footer: {
            Text(usernameHelp)
        }

        Section {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
            SecureField("Password (8+ characters)", text: $password)
                .textContentType(.newPassword)
            SecureField("Confirm password", text: $confirm)
                .textContentType(.newPassword)
            if !confirm.isEmpty && confirm != password {
                Text("Passwords don't match").font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Sign-in")
        } footer: {
            Text("People can add you to their Lounge by your email or @username. Nobody can browse a list of users.")
        }

        Section {
            Button {
                working = true
                Task {
                    let created = await jet.signUp(email: email, password: password, displayName: name, username: username)
                    if created, jet.isSignedIn { jet.setProfilePhoto(photoData) }
                    else if created { mode = .signIn }   // waiting on email confirmation
                    working = false
                }
            } label: {
                HStack { Spacer(); Text(working ? "Setting up..." : "Create my account").bold(); Spacer() }
            }
            .disabled(working || !canCreate)
        }
    }

    @ViewBuilder private var usernameBadge: some View {
        switch usernameState {
        case .empty: EmptyView()
        case .checking: ProgressView()
        case .available: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .taken, .invalid: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    private var usernameHelp: String {
        switch usernameState {
        case .empty, .checking, .available: return "3 to 20 characters: lowercase letters, numbers, dot or underscore."
        case .invalid: return "Use 3 to 20 lowercase letters, numbers, dots or underscores."
        case .taken: return "That username is taken. Try another."
        case .unknown: return "Couldn't check right now. You can still continue."
        }
    }

    // MARK: Existing account

    @ViewBuilder private var signInSections: some View {
        Section("Sign in") {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
            SecureField("Password", text: $password)
                .textContentType(.password)
        }
        Section {
            Button {
                working = true
                Task {
                    await jet.signIn(email: email, password: password)
                    working = false
                }
            } label: {
                HStack { Spacer(); Text(working ? "Signing in..." : "Sign in").bold(); Spacer() }
            }
            .disabled(working || !canSignIn)
        }
    }
}

/// Round profile picture, or a placeholder symbol.
struct ProfileAvatar: View {
    let data: Data?
    var size: CGFloat = 40
    var placeholder = "person.crop.circle.fill"

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: placeholder)
                    .resizable().scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}

extension UIImage {
    /// A small JPEG for the profile picture (keeps storage tiny).
    func avatarJPEG(maxSide: CGFloat) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).jpegData(withCompressionQuality: 0.8) { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
