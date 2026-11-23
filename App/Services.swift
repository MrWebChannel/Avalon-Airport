import Foundation
import EventKit
import UserNotifications
import AvalonCore

/// Storage through the iOS Files app. Dropbox, Box, Google Drive, OneDrive and iCloud all appear there,
/// so the Captain links a folder once and no provider login is needed. Read-only use only.
final class FilesStorageService: StorageService {
    private let key = "avalon.bookmarks"
    private var bookmarks: [String: Data]

    init() { bookmarks = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:] }

    func storeBookmark(for url: URL, connectorId: String) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        bookmarks[connectorId] = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmarks, forKey: key)
    }

    func resolve(_ connectorId: String) -> URL? {
        guard let data = bookmarks[connectorId] else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// The Files connector cannot create provider share links. Returning nil tells Ground Crew to ask
    /// the Captain to share the folder read-only in her storage app; the grant is still recorded and expires.
    func shareFolder(repository: Repository, folder: String, with recipientName: String) throws -> String? { nil }

    func revokeFolder(repository: Repository, folder: String, link: String?) throws {}

    func fileExists(repository: Repository, path: String) -> Bool {
        let root = resolve(repository.connectorId)
        let scoped = root?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { root?.stopAccessingSecurityScopedResource() } }
        return FileManager.default.fileExists(atPath: path)
    }
}

/// Posts ETAs and customs dates to the Captain's own calendar (which syncs Google and Outlook).
/// No airline ever sees the calendar.
final class EventKitCalendarService: CalendarService {
    private let store = EKEventStore()
    private let key = "avalon.calendarIds"
    private(set) var granted = false

    func requestAccess() async -> Bool {
        granted = (try? await store.requestFullAccessToEvents()) ?? false
        return granted
    }

    func upsertEvent(key eventKey: String, title: String, date: Date) throws {
        guard granted else { throw TowerError.notAuthorized("Calendar access has not been granted") }
        var ids = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        let event = ids[eventKey].flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = true
        event.startDate = date
        event.endDate = date.addingTimeInterval(3600)
        if event.calendar == nil { event.calendar = store.defaultCalendarForNewEvents }
        try store.save(event, span: .thisEvent)
        ids[eventKey] = event.eventIdentifier
        UserDefaults.standard.set(ids, forKey: key)
    }
}

/// Local notifications on the Captain's device: proposals to review, deliverables to file, customs reminders.
final class LocalNotificationService: NotificationService {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    func notify(recipientId: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
