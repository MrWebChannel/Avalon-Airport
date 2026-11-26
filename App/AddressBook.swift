import SwiftUI
import Contacts
import ContactsUI
import AvalonCore

/// The device address book. Avalon only reads it to find a matching card, and only writes through
/// Apple's own contact screen, where the person checks the card and taps Save. Nothing from the
/// address book is ever sent through Jet-Stream.
@MainActor
@Observable
final class AddressBook {
    private let store = CNContactStore()
    private(set) var status: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)

    /// Full access, or (iOS 18+) the contacts the person chose to share.
    var canLookUp: Bool {
        if status == .authorized { return true }
        if #available(iOS 18.0, *), status == .limited { return true }
        return false
    }
    var canAsk: Bool { status == .notDetermined }

    func requestAccess() async {
        _ = try? await store.requestAccess(for: .contacts)
        status = CNContactStore.authorizationStatus(for: .contacts)
    }

    func refreshStatus() { status = CNContactStore.authorizationStatus(for: .contacts) }

    private static let matchKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
        CNContactImageDataAvailableKey, CNContactThumbnailImageDataKey
    ] as [CNKeyDescriptor]

    /// The first contact with the card's email, else its phone number.
    func match(_ card: BusinessContact) -> CNContact? {
        guard canLookUp else { return nil }
        if let email = card.email,
           let found = try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingEmailAddress: email),
                                                  keysToFetch: Self.matchKeys).first {
            return found
        }
        if let phone = card.phone,
           let found = try? store.unifiedContacts(matching: CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phone)),
                                                  keysToFetch: Self.matchKeys).first {
            return found
        }
        return nil
    }

    /// The same contact with every key Apple's contact screen needs.
    func fullContact(_ identifier: String) -> CNContact? {
        try? store.unifiedContact(withIdentifier: identifier, keysToFetch: [CNContactViewController.descriptorForRequiredKeys()])
    }

    /// A new contact pre-filled from a business card, for Apple's "New Contact" screen.
    static func newContact(from card: BusinessContact, photo: Data?) -> CNMutableContact {
        let c = CNMutableContact()
        if let name = card.name {
            if let parts = PersonNameComponentsFormatter().personNameComponents(from: name), parts.givenName != nil {
                c.givenName = parts.givenName ?? ""
                c.familyName = parts.familyName ?? ""
            } else {
                c.givenName = name
            }
        } else {
            c.contactType = .organization
        }
        c.organizationName = card.organization ?? ""
        c.jobTitle = card.jobTitle ?? ""
        if let phone = card.phone { c.phoneNumbers = [CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: phone))] }
        if let email = card.email { c.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)] }
        if let site = card.website { c.urlAddresses = [CNLabeledValue(label: CNLabelWork, value: site as NSString)] }
        if let photo { c.imageData = photo }
        return c
    }
}

// MARK: - Business card view

/// A Hub, Airport or Airline business card with call, email and web links, and the native
/// "Add to Contacts" screen. If the person is already in Contacts, their own photo is shown.
struct BusinessCardView: View {
    @Environment(AddressBook.self) private var book
    let card: BusinessContact
    /// Shown under the name, e.g. the airline's role on this journey.
    var caption: String? = nil

    @State private var match: CNContact?
    @State private var sheet: CardSheet?
    @State private var preparing = false

    enum CardSheet: Identifiable {
        case new(CNMutableContact)
        case existing(CNContact)
        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let c): return c.identifier
            }
        }
    }

    private var clean: BusinessContact { card.sanitized() }

    var body: some View {
        let c = clean
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                avatar(for: c)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.displayName).bold()
                    if c.name != nil, let org = c.organization { Text(org).font(.caption) }
                    if let title = c.jobTitle { Text(title).font(.caption).foregroundStyle(.secondary) }
                    if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                if match != nil {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(.green)
                        .accessibilityLabel("In your contacts")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                if let phone = c.phone, let url = URL(string: "tel:" + phone.filter { "0123456789+".contains($0) }) {
                    Link(destination: url) { Label(phone, systemImage: "phone") }
                }
                if let email = c.email, let url = URL(string: "mailto:" + email) {
                    Link(destination: url) { Label(email, systemImage: "envelope") }
                }
                if let site = c.website, let url = URL(string: site) {
                    Link(destination: url) { Label(url.host() ?? site, systemImage: "safari") }
                }
            }
            .font(.callout)
            .buttonStyle(.borderless)

            HStack(spacing: 10) {
                if let match {
                    Button("View in Contacts") {
                        if let full = book.fullContact(match.identifier) { sheet = .existing(full) }
                    }
                } else {
                    Button(preparing ? "Preparing..." : "Add to Contacts") { prepareNewContact(c) }
                        .disabled(preparing)
                }
                if book.canAsk {
                    Button("Check my Contacts") {
                        Task { await book.requestAccess(); lookUp() }
                    }
                }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
        .padding(.vertical, 4)
        .task(id: book.status) { lookUp() }
        .sheet(item: $sheet, onDismiss: { book.refreshStatus(); lookUp() }) { item in
            switch item {
            case .new(let contact):
                ContactScreen(mode: .new(contact)) { sheet = nil }.ignoresSafeArea()
            case .existing(let contact):
                ContactScreen(mode: .existing(contact)) { sheet = nil }.ignoresSafeArea()
            }
        }
    }

    @ViewBuilder private func avatar(for c: BusinessContact) -> some View {
        let size: CGFloat = 48
        if let data = match?.thumbnailImageData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: size, height: size).clipShape(Circle())
        } else if let link = c.photoURL, let url = URL(string: link) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Monogram(text: c.displayName, size: size)
            }
            .frame(width: size, height: size).clipShape(Circle())
        } else {
            Monogram(text: c.displayName, size: size)
        }
    }

    private func lookUp() { match = book.match(clean) }

    private func prepareNewContact(_ c: BusinessContact) {
        preparing = true
        Task {
            var photo: Data?
            if let link = c.photoURL, let url = URL(string: link) {
                let result = try? await URLSession.shared.data(from: url)
                if let result, (result.1 as? HTTPURLResponse)?.statusCode == 200,
                   result.0.count < 5_000_000, UIImage(data: result.0) != nil {
                    photo = result.0
                }
            }
            sheet = .new(AddressBook.newContact(from: c, photo: photo))
            preparing = false
        }
    }
}

/// Initials on a colored circle, used when a card has no photo.
struct Monogram: View {
    let text: String
    var size: CGFloat = 48

    private var initials: String {
        let words = text.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.35))
            .frame(width: size, height: size)
            .overlay(Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white))
    }
}

/// Apple's contact screen: "New Contact" (the person checks it and taps Done to save) or an existing card.
struct ContactScreen: UIViewControllerRepresentable {
    enum Mode {
        case new(CNMutableContact)
        case existing(CNContact)
    }
    let mode: Mode
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller: CNContactViewController
        switch mode {
        case .new(let contact):
            controller = CNContactViewController(forNewContact: contact)
        case .existing(let contact):
            controller = CNContactViewController(for: contact)
            controller.allowsEditing = true
            controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
                systemItem: .done, primaryAction: UIAction { _ in context.coordinator.onDone() })
        }
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onDone()
        }
    }
}
