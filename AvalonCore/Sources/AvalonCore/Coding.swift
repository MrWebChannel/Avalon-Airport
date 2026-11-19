import Foundation

// MARK: - CalendarDay

/// A calendar date with no time or time zone, e.g. an ETA of `2026-11-25`.
/// Stored in `.avj` files as `YYYY-MM-DD`.
public struct CalendarDay: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`. Any time part after the date is ignored.
    public init?(string: String) {
        let datePart = string.trimmingCharacters(in: .whitespaces).prefix(10)
        let parts = datePart.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = CalendarDay(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(raw)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Board style, e.g. `NOV 25`.
    public var boardString: String {
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        return String(format: "%@ %02d", months[max(0, min(11, month - 1))], day)
    }

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func startOfDay(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public func adding(days: Int, calendar: Calendar = .current) -> CalendarDay {
        guard let start = startOfDay(in: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: start) else { return self }
        return CalendarDay(date: shifted, calendar: calendar)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

// MARK: - DefaultEmpty

/// Decodes a missing or null collection as empty, so `.avj` files can omit empty lists.
@propertyWrapper
public struct DefaultEmpty<T: Codable & RangeReplaceableCollection>: Codable {
    public var wrappedValue: T

    public init() { wrappedValue = T() }
    public init(wrappedValue: T) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? T() : try container.decode(T.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension DefaultEmpty: Equatable where T: Equatable {}
extension DefaultEmpty: Hashable where T: Hashable {}
extension DefaultEmpty: Sendable where T: Sendable {}

extension KeyedDecodingContainer {
    public func decode<T>(_ type: DefaultEmpty<T>.Type, forKey key: Key) throws -> DefaultEmpty<T> {
        try decodeIfPresent(type, forKey: key) ?? DefaultEmpty()
    }
}
