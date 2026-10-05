import Foundation

/// `GET /users/:userId/weekly-recap?week_start=YYYY-MM-DD` — one week, SUNDAY
/// to Saturday in the user's own days (the weekly challenge's week). The
/// server may send only the days that have something on them; `sevenDays`
/// fills the rest.
///
/// Decoded DEFENSIVELY, field by field: the endpoint is new, a shipped build
/// can't be updated when a field's shape turns out different, and ONE
/// mis-typed field in a synthesized decoder fails the whole screen. So every
/// field is optional, numbers accept a JSON number OR a numeric string (pg's
/// `numeric` serialises as a string), and an unreadable nested object reads
/// as absent rather than as an error. There are no timestamps in the contract
/// — dates are `date` strings, which are safe (ios.md, the fractional-seconds
/// decoder trap).
struct WeeklyRecap: Codable, Equatable {
    var weekStart: String
    var weekEnd: String?
    var isComplete: Bool?
    var totalMiles: Double?
    var priorWeekMiles: Double?
    var days: [Day]
    var daysGoalMet: Int?
    var goalMiles: Double?
    var workouts: Int?
    var totalDurationSeconds: Double?
    var longestWorkoutMiles: Double?
    var fastestMilePaceSeconds: Double?
    var currentStreak: Int?
    var streakAtWeekStart: Int?
    var weeklyChallenge: Challenge?
    var friends: Friends?
    var highlights: [String]

    struct Day: Codable, Equatable, Identifiable {
        var date: String
        var miles: Double
        var goalMet: Bool
        var covered: Bool
        var id: String { date }

        enum CodingKeys: String, CodingKey {
            case date, miles, goal_met, covered
        }

        init(date: String, miles: Double, goalMet: Bool, covered: Bool) {
            self.date = date
            self.miles = miles
            self.goalMet = goalMet
            self.covered = covered
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = (try? c.decode(String.self, forKey: .date)) ?? ""
            miles = c.lossyDouble(.miles) ?? 0
            goalMet = c.lossyBool(.goal_met) ?? false
            covered = c.lossyBool(.covered) ?? false
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(date, forKey: .date)
            try c.encode(miles, forKey: .miles)
            try c.encode(goalMet, forKey: .goal_met)
            try c.encode(covered, forKey: .covered)
        }

        /// The calendar day, parsed in the device's calendar — a `date`
        /// string names a local day, never an instant.
        var localDate: Date? { WeeklyRecap.dayFormatter.date(from: date) }
    }

    struct Challenge: Codable, Equatable {
        var name: String?
        var completed: Bool?
        var value: Double?
        var target: Double?
        var unit: String?
        /// Additive: the catalog key and an SF Symbol for the card's icon.
        var challengeKey: String?
        var icon: String?

        enum CodingKeys: String, CodingKey {
            case name, completed, value, target, unit, challenge_key, icon
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            challengeKey = try? c.decode(String.self, forKey: .challenge_key)
            icon = try? c.decode(String.self, forKey: .icon)
            name = try? c.decode(String.self, forKey: .name)
            completed = c.lossyBool(.completed)
            value = c.lossyDouble(.value)
            target = c.lossyDouble(.target)
            unit = try? c.decode(String.self, forKey: .unit)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(name, forKey: .name)
            try c.encodeIfPresent(completed, forKey: .completed)
            try c.encodeIfPresent(value, forKey: .value)
            try c.encodeIfPresent(target, forKey: .target)
            try c.encodeIfPresent(unit, forKey: .unit)
            try c.encodeIfPresent(challengeKey, forKey: .challenge_key)
            try c.encodeIfPresent(icon, forKey: .icon)
        }
    }

    struct Friends: Codable, Equatable {
        var rank: Int?
        var of: Int?
        var top: [Friend]

        enum CodingKeys: String, CodingKey { case rank, of, top }

        init(rank: Int?, of: Int?, top: [Friend]) {
            self.rank = rank
            self.of = of
            self.top = top
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rank = c.lossyInt(.rank)
            of = c.lossyInt(.of)
            top = (try? c.decode([Friend].self, forKey: .top)) ?? []
        }
    }

    struct Friend: Codable, Equatable, Identifiable {
        var userId: String
        var username: String?
        var firstName: String?
        var profileImageUrl: String?
        var miles: Double
        var isMe: Bool
        var id: String { userId }

        enum CodingKeys: String, CodingKey {
            case user_id, username, first_name, profile_image_url, miles, is_me
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            userId = (try? c.decode(String.self, forKey: .user_id)) ?? UUID().uuidString
            username = try? c.decode(String.self, forKey: .username)
            firstName = try? c.decode(String.self, forKey: .first_name)
            profileImageUrl = try? c.decode(String.self, forKey: .profile_image_url)
            miles = c.lossyDouble(.miles) ?? 0
            isMe = c.lossyBool(.is_me) ?? false
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(userId, forKey: .user_id)
            try c.encodeIfPresent(username, forKey: .username)
            try c.encodeIfPresent(firstName, forKey: .first_name)
            try c.encodeIfPresent(profileImageUrl, forKey: .profile_image_url)
            try c.encode(miles, forKey: .miles)
            try c.encode(isMe, forKey: .is_me)
        }

        /// What a podium prints: first name, else the handle.
        var displayName: String {
            if let firstName, !firstName.isEmpty { return firstName }
            if let username, !username.isEmpty { return username }
            return "Friend"
        }
    }

    enum CodingKeys: String, CodingKey {
        case week_start, week_end, is_complete, total_miles, prior_week_miles, days,
             days_goal_met, goal_miles, workouts, total_duration_seconds,
             longest_workout_miles, fastest_mile_pace_seconds, current_streak,
             streak_at_week_start, weekly_challenge, friends, highlights
    }

    init(weekStart: String, weekEnd: String?, isComplete: Bool?, totalMiles: Double?,
         priorWeekMiles: Double?, days: [Day], daysGoalMet: Int?, goalMiles: Double?,
         workouts: Int?, totalDurationSeconds: Double?, longestWorkoutMiles: Double?,
         fastestMilePaceSeconds: Double?, currentStreak: Int?, streakAtWeekStart: Int?,
         weeklyChallenge: Challenge? = nil, friends: Friends? = nil, highlights: [String] = []) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.isComplete = isComplete
        self.totalMiles = totalMiles
        self.priorWeekMiles = priorWeekMiles
        self.days = days
        self.daysGoalMet = daysGoalMet
        self.goalMiles = goalMiles
        self.workouts = workouts
        self.totalDurationSeconds = totalDurationSeconds
        self.longestWorkoutMiles = longestWorkoutMiles
        self.fastestMilePaceSeconds = fastestMilePaceSeconds
        self.currentStreak = currentStreak
        self.streakAtWeekStart = streakAtWeekStart
        self.weeklyChallenge = weeklyChallenge
        self.friends = friends
        self.highlights = highlights
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = (try? c.decode(String.self, forKey: .week_start)) ?? ""
        weekEnd = try? c.decode(String.self, forKey: .week_end)
        isComplete = c.lossyBool(.is_complete)
        totalMiles = c.lossyDouble(.total_miles)
        priorWeekMiles = c.lossyDouble(.prior_week_miles)
        days = ((try? c.decode([Day].self, forKey: .days)) ?? []).filter { !$0.date.isEmpty }
        daysGoalMet = c.lossyInt(.days_goal_met)
        goalMiles = c.lossyDouble(.goal_miles)
        workouts = c.lossyInt(.workouts)
        totalDurationSeconds = c.lossyDouble(.total_duration_seconds)
        longestWorkoutMiles = c.lossyDouble(.longest_workout_miles)
        fastestMilePaceSeconds = c.lossyDouble(.fastest_mile_pace_seconds)
        currentStreak = c.lossyInt(.current_streak)
        streakAtWeekStart = c.lossyInt(.streak_at_week_start)
        weeklyChallenge = try? c.decode(Challenge.self, forKey: .weekly_challenge)
        friends = try? c.decode(Friends.self, forKey: .friends)
        highlights = ((try? c.decode([String].self, forKey: .highlights)) ?? [])
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(weekStart, forKey: .week_start)
        try c.encodeIfPresent(weekEnd, forKey: .week_end)
        try c.encodeIfPresent(isComplete, forKey: .is_complete)
        try c.encodeIfPresent(totalMiles, forKey: .total_miles)
        try c.encodeIfPresent(priorWeekMiles, forKey: .prior_week_miles)
        try c.encode(days, forKey: .days)
        try c.encodeIfPresent(daysGoalMet, forKey: .days_goal_met)
        try c.encodeIfPresent(goalMiles, forKey: .goal_miles)
        try c.encodeIfPresent(workouts, forKey: .workouts)
        try c.encodeIfPresent(totalDurationSeconds, forKey: .total_duration_seconds)
        try c.encodeIfPresent(longestWorkoutMiles, forKey: .longest_workout_miles)
        try c.encodeIfPresent(fastestMilePaceSeconds, forKey: .fastest_mile_pace_seconds)
        try c.encodeIfPresent(currentStreak, forKey: .current_streak)
        try c.encodeIfPresent(streakAtWeekStart, forKey: .streak_at_week_start)
        try c.encodeIfPresent(weeklyChallenge, forKey: .weekly_challenge)
        try c.encodeIfPresent(friends, forKey: .friends)
        try c.encode(highlights, forKey: .highlights)
    }

    // MARK: Derived

    /// "Sep 14 – 20" / "Aug 31 – Sep 6".
    var rangeText: String {
        guard let start = WeeklyRecap.dayFormatter.date(from: weekStart) else { return "" }
        let end = weekEnd.flatMap { WeeklyRecap.dayFormatter.date(from: $0) }
            ?? Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let cal = Calendar.current
        let startText = WeeklyRecap.monthDay.string(from: start)
        if cal.component(.month, from: start) == cal.component(.month, from: end) {
            return "\(startText) – \(cal.component(.day, from: end))"
        }
        return "\(startText) – \(WeeklyRecap.monthDay.string(from: end))"
    }

    /// Always seven entries, from `week_start` (a Sunday), so the strip never draws a short
    /// week — a missing day from the server is a day with nothing on it.
    var sevenDays: [Day] {
        guard let start = WeeklyRecap.dayFormatter.date(from: weekStart) else { return days }
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        return (0..<7).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = WeeklyRecap.dayFormatter.string(from: date)
            return byDate[key] ?? Day(date: key, miles: 0, goalMet: false, covered: false)
        }
    }

    /// Goal days, counted from the strip when the server didn't say.
    var goalDays: Int {
        daysGoalMet ?? days.filter { $0.goalMet || $0.covered }.count
    }

    /// Change against last week, as a fraction (0.33 = +33%). nil when there
    /// is nothing to compare against — a first week has no "vs".
    var deltaFraction: Double? {
        guard let prior = priorWeekMiles, prior > 0.05, let total = totalMiles else { return nil }
        return (total - prior) / prior
    }

    /// The streak's growth over the week, when both ends are known.
    var streakGain: Int? {
        guard let now = currentStreak, let before = streakAtWeekStart, now > before else { return nil }
        return now - before
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    /// Sunday of the week containing `date`, as the server's `week_start` —
    /// the weekly challenge's Sunday→Saturday week, in local days.
    static func weekStart(containing date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        cal.timeZone = .current
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        return dayFormatter.string(from: start)
    }

    /// The week before `weekStart` (or after, for a positive offset).
    static func shift(_ weekStart: String, weeks: Int) -> String? {
        guard let start = dayFormatter.date(from: weekStart),
              let moved = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: start) else { return nil }
        return dayFormatter.string(from: moved)
    }
}

// MARK: - Lossy decoding

extension KeyedDecodingContainer {
    /// A number sent as a JSON number OR as a numeric string.
    func lossyDouble(_ key: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    func lossyInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let d = lossyDouble(key) { return Int(d.rounded()) }
        return nil
    }

    func lossyBool(_ key: Key) -> Bool? {
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return ["true", "t", "1", "yes"].contains(s.lowercased())
        }
        return nil
    }
}
