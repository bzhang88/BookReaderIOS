import Foundation

/// Pure time-of-day check for the eye-care filter's optional auto-schedule -- handles a window that
/// wraps past midnight (e.g. 20...6 means "8pm to 6am the next day"), which a naive `start <= hour
/// && hour < end` comparison would get backwards.
enum EyeCareSchedule {
    static func isActive(startHour: Int, endHour: Int, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard startHour != endHour else { return false }
        let hour = calendar.component(.hour, from: now)
        if startHour < endHour {
            return hour >= startHour && hour < endHour
        } else {
            return hour >= startHour || hour < endHour
        }
    }
}
