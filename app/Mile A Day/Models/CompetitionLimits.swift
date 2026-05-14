import Foundation

enum CompetitionLimits {
    /// Maximum length, in characters, of a user-supplied competition name.
    /// Keep in sync with COMPETITION_NAME_MAX_LENGTH in
    /// backend/src/services/competitionService.ts
    static let nameMaxLength = 50
}
