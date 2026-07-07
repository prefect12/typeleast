import XCTest
@testable import Typeleast

final class ActivityCalendarLayoutTests: XCTestCase {
    func testCurrentWeekOmitsFutureDates() throws {
        let calendar = Self.utcCalendar
        let today = try Self.date(year: 2026, month: 7, day: 7, calendar: calendar)
        let weeks = ActivityCalendarLayout.generateWeeks(
            activeDates: [],
            today: today,
            calendar: calendar,
            minimumActivityDays: 7
        )

        let lastWeek = try XCTUnwrap(weeks.last)
        XCTAssertEqual(
            lastWeek,
            try [
                Self.date(year: 2026, month: 7, day: 5, calendar: calendar),
                Self.date(year: 2026, month: 7, day: 6, calendar: calendar),
                Self.date(year: 2026, month: 7, day: 7, calendar: calendar)
            ]
        )
        XCTAssertFalse(
            weeks.flatMap { $0 }.contains(
                try Self.date(year: 2026, month: 7, day: 8, calendar: calendar)
            )
        )
    }

    func testPastWeeksRemainComplete() throws {
        let calendar = Self.utcCalendar
        let today = try Self.date(year: 2026, month: 7, day: 7, calendar: calendar)
        let weeks = ActivityCalendarLayout.generateWeeks(
            activeDates: [],
            today: today,
            calendar: calendar,
            minimumActivityDays: 14
        )

        XCTAssertEqual(weeks.dropLast().map(\.count), [7, 7])
        XCTAssertEqual(weeks.last?.count, 3)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
