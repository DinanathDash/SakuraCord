import Foundation

public struct DiscordParsedTimeCandidate: Equatable, Sendable {
    public struct Option: Identifiable, Equatable, Sendable {
        public let id: String
        public let style: String?
        public let displayText: String
        public let markdownToken: String

        public init(id: String, style: String?, displayText: String, markdownToken: String) {
            self.id = id
            self.style = style
            self.displayText = displayText
            self.markdownToken = markdownToken
        }
    }

    public let date: Date
    public let options: [Option]

    public init(date: Date, options: [Option]) {
        self.date = date
        self.options = options
    }
}

public enum DiscordNaturalLanguageTimeParser {
    public static func candidates(
        for query: String,
        now: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [DiscordParsedTimeCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("now") == .orderedSame {
            return [makeCandidate(for: now, isNow: true, now: now, locale: locale, timeZone: timeZone, calendar: calendar)]
        }

        if let seconds = Int64(trimmed), seconds > 100_000_000, seconds < 100_000_000_000 {
            let date = Date(timeIntervalSince1970: TimeInterval(seconds))
            return [makeCandidate(for: date, isNow: false, now: now, locale: locale, timeZone: timeZone, calendar: calendar)]
        }

        if let relativeDate = parseRelative(query: trimmed, now: now, calendar: calendar) {
            return [makeCandidate(for: relativeDate, isNow: false, now: now, locale: locale, timeZone: timeZone, calendar: calendar)]
        }

        let dates = parseNaturalDates(query: trimmed, now: now, calendar: calendar)
        return dates.map {
            makeCandidate(for: $0, isNow: false, now: now, locale: locale, timeZone: timeZone, calendar: calendar)
        }
    }

    private static func makeCandidate(
        for date: Date,
        isNow: Bool,
        now: Date,
        locale: Locale,
        timeZone: TimeZone,
        calendar: Calendar
    ) -> DiscordParsedTimeCandidate {
        let seconds = Int64(date.timeIntervalSince1970)
        let shortText: String
        let shortStyle: String?
        if isNow {
            shortText = Date.FormatStyle(date: .numeric, time: .standard, locale: locale, calendar: calendar, timeZone: timeZone).format(date)
            shortStyle = "T"
        } else {
            shortText = Date.FormatStyle(date: .numeric, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone).format(date)
            shortStyle = "f"
        }

        let longText = Date.FormatStyle(date: .long, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone).format(date)
        let fullText = Date.FormatStyle(date: .complete, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone).format(date)
        let relativeText = DiscordTimestampFormatter.relativeText(for: date, relativeTo: now, locale: locale)

        let options: [DiscordParsedTimeCandidate.Option] = [
            .init(
                id: "\(seconds)-short",
                style: shortStyle,
                displayText: shortText,
                markdownToken: shortStyle == nil ? "<t:\(seconds)>" : "<t:\(seconds):\(shortStyle!)>"
            ),
            .init(
                id: "\(seconds)-long",
                style: "f",
                displayText: longText,
                markdownToken: "<t:\(seconds):f>"
            ),
            .init(
                id: "\(seconds)-full",
                style: "F",
                displayText: fullText,
                markdownToken: "<t:\(seconds):F>"
            ),
            .init(
                id: "\(seconds)-relative",
                style: "R",
                displayText: relativeText,
                markdownToken: "<t:\(seconds):R>"
            )
        ]
        return DiscordParsedTimeCandidate(date: date, options: options)
    }

    private static func parseRelative(query: String, now: Date, calendar: Calendar) -> Date? {
        let lower = query.lowercased()
        let inPattern = #"^in\s+(\d+)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|wk|wks|week|weeks|mo|month|months|y|yr|yrs|year|years)$"#
        let agoPattern = #"^(\d+)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|wk|wks|week|weeks|mo|month|months|y|yr|yrs|year|years)\s+ago$"#

        if let regex = try? NSRegularExpression(pattern: inPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let valRange = Range(match.range(at: 1), in: lower),
           let unitRange = Range(match.range(at: 2), in: lower),
           let val = Int(lower[valRange]) {
            return resolveOffset(value: val, unit: String(lower[unitRange]), sign: 1, now: now, calendar: calendar)
        }

        if let regex = try? NSRegularExpression(pattern: agoPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let valRange = Range(match.range(at: 1), in: lower),
           let unitRange = Range(match.range(at: 2), in: lower),
           let val = Int(lower[valRange]) {
            return resolveOffset(value: val, unit: String(lower[unitRange]), sign: -1, now: now, calendar: calendar)
        }

        return nil
    }

    private static func resolveOffset(
        value: Int,
        unit: String,
        sign: Int,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let delta = sign * value
        switch unit {
        case "s", "sec", "secs", "second", "seconds":
            return calendar.date(byAdding: .second, value: delta, to: now)
        case "m", "min", "mins", "minute", "minutes":
            return calendar.date(byAdding: .minute, value: delta, to: now)
        case "h", "hr", "hrs", "hour", "hours":
            return calendar.date(byAdding: .hour, value: delta, to: now)
        case "d", "day", "days":
            return calendar.date(byAdding: .day, value: delta, to: now)
        case "w", "wk", "wks", "week", "weeks":
            return calendar.date(byAdding: .day, value: delta * 7, to: now)
        case "mo", "month", "months":
            return calendar.date(byAdding: .month, value: delta, to: now)
        case "y", "yr", "yrs", "year", "years":
            return calendar.date(byAdding: .year, value: delta, to: now)
        default:
            return nil
        }
    }

    private static func parseNaturalDates(query: String, now: Date, calendar: Calendar) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }
        let range = NSRange(query.startIndex..., in: query)
        let matches = detector.matches(in: query, range: range)
        guard let match = matches.first, let baseDate = match.date else {
            return []
        }

        let hasExplicitYear = query.range(of: #"\b(19\d\d|20\d\d)\b"#, options: .regularExpression) != nil
        if hasExplicitYear {
            return [baseDate]
        }

        if baseDate < now {
            if let future = calendar.date(byAdding: .year, value: 1, to: baseDate) {
                return [future, baseDate]
            }
        } else {
            if let past = calendar.date(byAdding: .year, value: -1, to: baseDate) {
                return [baseDate, past]
            }
        }

        return [baseDate]
    }
}
