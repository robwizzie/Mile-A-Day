import Foundation

/// A single recorded daily-challenge completion.
///
/// `date` is always normalized to the start of the user's local day so we can
/// de-dupe by calendar day and do day-based lookups without ambiguity.
struct ChallengeCompletion: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let challengeKey: String
    let title: String
    let icon: String
    let description: String

    init(
        id: UUID = UUID(),
        date: Date,
        challengeKey: String,
        title: String,
        icon: String,
        description: String
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.challengeKey = challengeKey
        self.title = title
        self.icon = icon
        self.description = description
    }
}
