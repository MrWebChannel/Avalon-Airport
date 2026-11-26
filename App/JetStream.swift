import Foundation
import Observation
import Security
import AvalonCore

/// Where Jet-Stream lives. The publishable key is meant to ship inside the app: the database rules
/// (sender can't be faked, only the addressee can read) protect the data, not the key.
/// Never put the project's secret key in the app.
enum JetStreamConfig {
    static let url = URL(string: "https://tdelngumhgbmyfgzmeoi.supabase.co")!
    static let publishableKey = "sb_publishable_fDcLriIfjZYpDUlynULzhg_7dY6ZLxW"
    /// Background update check while the app is open. The Lounge checks every few seconds on its own.
    static let backgroundCheckSeconds: Double = 60
    static let loungeCheckSeconds: Double = 4
}

enum JetStreamError: LocalizedError {
    case notSignedIn
    case server(String)
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to Jet-Stream first"
        case .server(let message): return message
        }
    }
}

/// Someone this device sends Lounge messages to. Found by exact email, or added when they message you.
struct JetStreamContact: Codable, Identifiable, Hashable {
    var id: String          // Jet-Stream account id
    var name: String
    var email: String?
}

struct LoungeChatMessage: Codable, Identifiable, Hashable {
    var id: String
    var thread: String
    var threadTitle: String?
    var fromId: String
    var fromName: String
    var text: String
    var at: Date
    var mine: Bool
    /// For messages I sent: one Jet-Stream row per recipient, and how many have been applied (received).
    var rowIds: [String] = []
    var deliveredCount: Int = 0
}

/// The Jet-Stream client: account, Lounge contacts and messages, and the update check.
/// Plain HTTPS to Supabase (no SDK), so the app keeps a single third-party dependency.
@MainActor
@Observable
final class JetStream {
    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userId: String
        var email: String
        var displayName: String
    }

    private(set) var session: Session?
    private(set) var contacts: [JetStreamContact] = []
    private(set) var messages: [LoungeChatMessage] = []
    private(set) var lastCheck: Date?
    var unread = 0
    var errorMessage: String?
    var noticeMessage: String?

    var isSignedIn: Bool { session != nil }
    var myId: String? { session?.userId }
    var myName: String { session?.displayName ?? "Me" }

    private var checking = false
    private let sessionAccount = "session"
    private var storeURL: URL { URL.documentsDirectory.appending(path: "avalon-lounge.json") }

    init() {
        if let data = Keychain.load(account: sessionAccount) {
            session = try? JSONDecoder().decode(Session.self, from: data)
        }
        loadStore()
    }

    // MARK: Account

    func signUp(email: String, password: String, displayName: String) async {
        do {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: [String: Any] = [
                "email": email.trimmingCharacters(in: .whitespaces),
                "password": password,
                "data": ["display_name": name.isEmpty ? email : name]
            ]
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await send("auth/v1/signup", method: "POST", body: body, auth: false)
            let reply = try JSONDecoder().decode(AuthReply.self, from: data)
            if reply.access_token != nil {
                try adopt(reply, fallbackName: name)
            } else {
                noticeMessage = "Account created. Confirm the email Supabase sent, then sign in."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: [
                "email": email.trimmingCharacters(in: .whitespaces), "password": password
            ])
            let data = try await send("auth/v1/token", method: "POST", query: [URLQueryItem(name: "grant_type", value: "password")],
                                      body: body, auth: false)
            try adopt(try JSONDecoder().decode(AuthReply.self, from: data), fallbackName: nil)
            await loadMyName()
            await check()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        session = nil
        Keychain.delete(account: sessionAccount)
    }

    private func adopt(_ reply: AuthReply, fallbackName: String?) throws {
        guard let access = reply.access_token, let refresh = reply.refresh_token, let user = reply.user else {
            throw JetStreamError.server("Jet-Stream did not return a session")
        }
        let name = user.user_metadata?.display_name ?? fallbackName ?? session?.displayName ?? user.email ?? "Me"
        session = Session(accessToken: access, refreshToken: refresh,
                          expiresAt: Date().addingTimeInterval(reply.expires_in ?? 3600),
                          userId: user.id, email: user.email ?? "", displayName: name)
        saveSession()
    }

    private func loadMyName() async {
        guard let me = myId else { return }
        if let data = try? await send("rest/v1/profiles", query: [
                URLQueryItem(name: "select", value: "display_name"), URLQueryItem(name: "id", value: "eq.\(me)")]),
           let rows = try? JSONDecoder().decode([ProfileRow].self, from: data),
           let name = rows.first?.display_name, !name.isEmpty {
            session?.displayName = name
            saveSession()
        }
    }

    // MARK: Contacts

    func addContact(email: String) async {
        do {
            let body = try JSONSerialization.data(withJSONObject: ["p_email": email])
            let data = try await send("rest/v1/rpc/jetstream_find_user", method: "POST", body: body)
            guard let found = try JSONDecoder().decode([ProfileRow].self, from: data).first, let id = found.id else {
                errorMessage = "No Avalon account uses that email yet. Ask them to create one in the Lounge."
                return
            }
            guard id != myId else { errorMessage = "That's your own account"; return }
            upsertContact(JetStreamContact(id: id, name: found.display_name ?? email, email: email))
            noticeMessage = "\(found.display_name ?? email) added to the Lounge"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeContact(_ contact: JetStreamContact) {
        contacts.removeAll { $0.id == contact.id }
        saveStore()
    }

    private func upsertContact(_ contact: JetStreamContact) {
        if let i = contacts.firstIndex(where: { $0.id == contact.id }) {
            if contacts[i].email == nil { contacts[i].email = contact.email }
        } else {
            contacts.append(contact)
        }
        saveStore()
    }

    // MARK: Sending

    /// One copy per Lounge contact, all in a single request. The sender decides who receives it.
    func sendLounge(_ text: String, thread: String, threadTitle: String?) async {
        guard let me = myId else { errorMessage = JetStreamError.notSignedIn.localizedDescription; return }
        guard !contacts.isEmpty else { errorMessage = "Add someone to the Lounge first (People button)"; return }
        do {
            let package = try JetStreamPackage.lounge(text: text, from: myName, thread: thread, threadTitle: threadTitle, at: Date())
            let yaml = try package.yaml()
            let rows = contacts.map { ["recipient_id": $0.id, "yaml_body": yaml] }
            let data = try await send("rest/v1/messages", method: "POST", body: try JSONSerialization.data(withJSONObject: rows),
                                      prefer: "return=representation")
            let created = try JSONDecoder().decode([IdRow].self, from: data)
            messages.append(LoungeChatMessage(id: UUID().uuidString, thread: thread, threadTitle: threadTitle,
                                              fromId: me, fromName: myName, text: package.text, at: package.sentAt,
                                              mine: true, rowIds: created.map(\.id)))
            saveStore()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Update check

    /// Pulls my unapplied packages, keeps the Lounge ones, marks them applied, and refreshes delivery ticks.
    /// Packages of a kind this build does not know are left waiting for a newer build.
    func check() async {
        guard let me = myId, !checking else { return }
        checking = true
        defer { checking = false; lastCheck = Date() }
        do {
            let data = try await send("rest/v1/messages", query: [
                URLQueryItem(name: "select", value: "id,sender_id,yaml_body"),
                URLQueryItem(name: "recipient_id", value: "eq.\(me)"),
                URLQueryItem(name: "status", value: "eq.sent"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ])
            let rows = try JSONDecoder().decode([MessageRow].self, from: data)
            var handled: [String] = []
            for row in rows {
                guard let package = try? JetStreamPackage.fromYAML(row.yaml_body), package.kind == .lounge else { continue }
                if !messages.contains(where: { $0.id == row.id }) {
                    messages.append(LoungeChatMessage(id: row.id, thread: package.thread, threadTitle: package.threadTitle,
                                                      fromId: row.sender_id, fromName: package.fromName, text: package.text,
                                                      at: package.sentAt, mine: false))
                    unread += 1
                }
                upsertContact(JetStreamContact(id: row.sender_id, name: package.fromName, email: nil))
                handled.append(row.id)
            }
            if !handled.isEmpty {
                messages.sort { $0.at < $1.at }
                try await markApplied(handled)
                saveStore()
            }
            try await refreshDelivery()
        } catch {
            // A failed background check stays quiet; the next one retries. Only sign-in problems surface.
            if case JetStreamError.notSignedIn = error { errorMessage = error.localizedDescription }
        }
    }

    private func markApplied(_ ids: [String]) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "status": "applied", "applied_at": ISO8601DateFormatter().string(from: Date())
        ])
        _ = try await send("rest/v1/messages", method: "PATCH",
                           query: [URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))")],
                           body: body, prefer: "return=minimal")
    }

    /// For my own messages still waiting on someone: how many recipients have applied them.
    private func refreshDelivery() async throws {
        let waiting = messages.filter { $0.mine && $0.deliveredCount < $0.rowIds.count }
        let ids = waiting.flatMap(\.rowIds)
        guard !ids.isEmpty else { return }
        let data = try await send("rest/v1/messages", query: [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "status", value: "eq.applied"),
            URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))")
        ])
        let applied = Set(try JSONDecoder().decode([IdRow].self, from: data).map(\.id))
        var changed = false
        for i in messages.indices where messages[i].mine {
            let count = messages[i].rowIds.filter { applied.contains($0) }.count
            if count > messages[i].deliveredCount { messages[i].deliveredCount = count; changed = true }
        }
        if changed { saveStore() }
    }

    // MARK: HTTPS

    private func send(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil,
                      auth: Bool = true, prefer: String? = nil) async throws -> Data {
        var components = URLComponents(url: JetStreamConfig.url.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(JetStreamConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if auth { request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw JetStreamError.server(Self.serverMessage(data) ?? "Jet-Stream error \(code)")
        }
        return data
    }

    private func validAccessToken() async throws -> String {
        guard let current = session else { throw JetStreamError.notSignedIn }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refreshToken])
            let data = try await send("auth/v1/token", method: "POST",
                                      query: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: body, auth: false)
            try adopt(try JSONDecoder().decode(AuthReply.self, from: data), fallbackName: current.displayName)
            return session?.accessToken ?? current.accessToken
        } catch JetStreamError.server(_) {
            // The refresh was refused (expired or revoked). A network blip just retries next check.
            signOut()
            throw JetStreamError.notSignedIn
        }
    }

    private static func serverMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["msg", "error_description", "message", "error"] {
            if let text = object[key] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    // MARK: Local storage

    private struct Store: Codable {
        var contacts: [JetStreamContact]
        var messages: [LoungeChatMessage]
    }

    private func saveSession() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        Keychain.save(data, account: sessionAccount)
    }

    private func saveStore() {
        if let data = try? JSONEncoder().encode(Store(contacts: contacts, messages: messages)) {
            try? data.write(to: storeURL, options: [.atomic, .completeFileProtection])
        }
    }

    private func loadStore() {
        guard let data = try? Data(contentsOf: storeURL), let store = try? JSONDecoder().decode(Store.self, from: data) else { return }
        contacts = store.contacts
        messages = store.messages
    }
}

// MARK: - Wire formats (Supabase field names)

private struct AuthReply: Decodable {
    struct User: Decodable {
        struct Meta: Decodable { var display_name: String? }
        var id: String
        var email: String?
        var user_metadata: Meta?
    }
    var access_token: String?
    var refresh_token: String?
    var expires_in: Double?
    var user: User?
}

private struct ProfileRow: Decodable {
    var id: String?
    var display_name: String?
}

private struct MessageRow: Decodable {
    var id: String
    var sender_id: String
    var yaml_body: String
}

private struct IdRow: Decodable { var id: String }

// MARK: - Keychain (the Jet-Stream session never sits in plain files)

enum Keychain {
    private static let service = "studio.hcs.avalon.jetstream"

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ data: Data, account: String) {
        SecItemDelete(base(account) as CFDictionary)
        var item = base(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(account: String) -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }
}
