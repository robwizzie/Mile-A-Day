import SwiftUI

// MARK: - Prominent Banner (for detail views)

/// Full-width warning banner for workout detail views — impossible to miss
struct ManualWorkoutBanner: View {
    let source: String?

    private var isManual: Bool { source == "manual" }
    private var isEdited: Bool { source == "edited" }

    var body: some View {
        if isManual || isEdited {
            HStack(spacing: 8) {
                Image(systemName: isManual ? "exclamationmark.triangle.fill" : "pencil.circle.fill")
                    .font(.system(size: 14, weight: .semibold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(isManual ? "Manually Entered" : "Manually Edited")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(isManual
                         ? "This workout was not recorded by a device"
                         : "Distance or duration was changed by the user")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.8)
                }

                Spacer()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.85))
            )
        }
    }
}

/// Overload accepting WorkoutSource enum directly
extension ManualWorkoutBanner {
    init(source: WorkoutSource) {
        self.init(source: source.rawValue)
    }
}

// MARK: - Inline Capsule Badge (for rows and cards)

/// Capsule badge for workout rows — clearly visible next to workout type
struct ManualWorkoutBadge: View {
    let source: WorkoutSource

    var body: some View {
        if source == .manual || source == .edited {
            HStack(spacing: 3) {
                Image(systemName: source == .manual ? "exclamationmark.triangle.fill" : "pencil.circle.fill")
                    .font(.system(size: 9))
                Text(source == .manual ? "Manual" : "Edited")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.orange)
            )
        }
    }
}

// MARK: - Compact Icon (for tight list rows)

/// Icon-only indicator for compact spaces
struct ManualWorkoutIcon: View {
    let source: WorkoutSource

    var body: some View {
        if source == .manual || source == .edited {
            Image(systemName: source == .manual ? "exclamationmark.triangle.fill" : "pencil.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange)
        }
    }
}

// MARK: - String-Based Variants (for backend API models)

/// Badge accepting a raw source string from the backend
struct ManualWorkoutBadgeFromString: View {
    let source: String?

    var body: some View {
        if let source = source, let ws = WorkoutSource(rawValue: source) {
            ManualWorkoutBadge(source: ws)
        }
    }
}

/// Icon accepting a raw source string from the backend
struct ManualWorkoutIconFromString: View {
    let source: String?

    var body: some View {
        if let source = source, let ws = WorkoutSource(rawValue: source) {
            ManualWorkoutIcon(source: ws)
        }
    }
}
