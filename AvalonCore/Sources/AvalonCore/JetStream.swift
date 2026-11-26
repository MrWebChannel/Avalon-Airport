import Foundation
import Yams

// Jet-Stream is the plain transport between Avalon apps (a Supabase project).
// Every account is just a user. The sending app decides who receives each package and sends one
// copy per recipient. The server only guarantees the envelope: the sender cannot be faked, only the
// addressee can read a package, and the YAML cannot change after it is sent.
//
// Avalon carries status and conversation, never documents. A package is one small YAML file.

public enum JetStreamKind: String, Codable, Sendable {
    /// A Lounge chat message. Airlines never receive these.
    case lounge
}

/// One YAML package carried by Jet-Stream.
public struct JetStreamPackage: Codable, Hashable, Sendable {
    public var schemaVersion: String = AvalonVersion.schema
    public var kind: JetStreamKind
    /// Groups messages into one conversation, e.g. a journey id.
    public var thread: String
    public var threadTitle: String?
    /// Display name only. The sender's account id comes from the Jet-Stream envelope, not from here.
    public var fromName: String
    public var text: String
    public var sentAt: Date

    public init(kind: JetStreamKind, thread: String, threadTitle: String? = nil,
                fromName: String, text: String, sentAt: Date) {
        self.kind = kind; self.thread = thread; self.threadTitle = threadTitle
        self.fromName = fromName; self.text = text; self.sentAt = sentAt
    }

    /// Jet-Stream rejects anything over 256 KB.
    public static let maxBytes = 262_144

    public func yaml() throws -> String {
        let text = try YAMLEncoder().encode(self)
        guard text.utf8.count <= Self.maxBytes else { throw TowerError.invalid("Message is too long for Jet-Stream") }
        return text
    }

    public static func fromYAML(_ text: String) throws -> JetStreamPackage {
        try YAMLDecoder().decode(JetStreamPackage.self, from: text)
    }

    /// A Lounge message ready to send. Empty text is refused.
    public static func lounge(text: String, from name: String, thread: String, threadTitle: String?, at date: Date) throws -> JetStreamPackage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TowerError.invalid("Message is empty") }
        return JetStreamPackage(kind: .lounge, thread: thread, threadTitle: threadTitle,
                                fromName: name, text: trimmed, sentAt: date)
    }
}
