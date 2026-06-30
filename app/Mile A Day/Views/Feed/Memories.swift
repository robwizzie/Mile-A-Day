import SwiftUI

/// A walk/run the user did on today's calendar day in a previous year.
struct MemoryItem: Identifiable {
    let id = UUID()
    let date: Date
    let yearsAgo: Int
    let miles: Double
    let workoutType: String
    let durationSeconds: Double

    var yearsAgoText: String { yearsAgo == 1 ? "1 year ago" : "\(yearsAgo) years ago" }
}

/// Builds "On this day" memories from the locally-cached HealthKit workout
/// index — no network needed. Future: attach a post photo when one exists for
/// that date, and surface memories as a leading story ring.
enum MemoriesService {
    static func onThisDay(using hk: HealthKitManager) -> [MemoryItem] {
        guard let index = hk.workoutIndex else { return [] }
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day, .year], from: Date())
        guard let month = today.month, let day = today.day, let curYear = today.year else { return [] }

        var out: [MemoryItem] = []
        for (_, records) in index.workoutsByDate {
            guard let first = records.first else { continue }
            let comps = cal.dateComponents([.month, .day, .year], from: first.localDate)
            guard comps.month == month, comps.day == day, let year = comps.year, year < curYear else { continue }
            let miles = records.reduce(0.0) { $0 + $1.distance }
            guard miles >= 0.95 else { continue }
            let topType = records.max(by: { $0.distance < $1.distance })?.workoutType ?? "running"
            let duration = records.reduce(0.0) { $0 + $1.duration }
            out.append(MemoryItem(
                date: first.localDate,
                yearsAgo: curYear - year,
                miles: miles,
                workoutType: topType,
                durationSeconds: duration
            ))
        }
        return out.sorted { $0.yearsAgo < $1.yearsAgo }
    }
}

/// Compact "On this day" card shown at the top of the feed when memories exist.
struct MemoriesCardView: View {
    let memories: [MemoryItem]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(MADTheme.Colors.redGradient))

                VStack(alignment: .leading, spacing: 2) {
                    Text("On this day")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.6))
                    if let top = memories.first {
                        Text("\(top.yearsAgoText) · \(String(format: "%.2f", top.miles)) mi \(ActivityCardView.verb(top.workoutType).lowercased())")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if memories.count > 1 {
                    Text("+\(memories.count - 1)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(MADTheme.Colors.madRed.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Full list of today's memories across past years.
struct MemoriesDetailView: View {
    let memories: [MemoryItem]
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.md) {
                        ForEach(memories) { memory in
                            row(memory)
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("On this day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ memory: MemoryItem) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: ActivityCardView.icon(memory.workoutType))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(ActivityCardView.color(memory.workoutType))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.06)))

            VStack(alignment: .leading, spacing: 3) {
                Text(memory.yearsAgoText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(Self.dateFormatter.string(from: memory.date))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(String(format: "%.2f", memory.miles)) mi")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                if memory.durationSeconds > 0 {
                    Text(RunStatsStickerView.durationText(memory.durationSeconds))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .monospacedDigit()
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
