import SwiftUI

/// A one-day event (Champ 5K Day) for the Dashboard and the top of Compete:
/// the ring with Flamey in the gear, then where you stand — days to go, your
/// miles on the day, or the result. Draws nothing between events. The load
/// starts in `init` because an empty body gets no lifecycle.
struct SpecialEventCard: View {
    private let service = SpecialEventService.shared
    @State private var open: SpecialEvent?

    init() {
        Task { await SpecialEventService.shared.refreshIfStale() }
    }

    var body: some View {
        if let event = service.events.first {
            Button {
                MADHaptics.tap()
                open = event
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    SpecialEventStage(event: event, height: 128, compact: true) {
                        SpecialEventCaption(event: event, compact: true)
                    }
                    SpecialEventStatus(event: event)
                }
                .padding(DashboardCardSurface.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DashboardCardSurface(style: .fun))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens \(event.title)")
            .sheet(item: $open) { event in
                NavigationStack {
                    SpecialEventView(eventId: event.event_id)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { open = nil }
                                    .fontWeight(.semibold)
                            }
                        }
                }
                .madTypeCap(.accessibility1)
                .preferredColorScheme(.dark)
            }
        }
    }
}

/// The eyebrow + title over the ring.
struct SpecialEventCaption: View {
    let event: SpecialEvent
    var compact = false

    private var eyebrow: String {
        switch event.phase {
        case .upcoming: return compact ? event.dayLine : "One day only · \(event.shortDay)"
        case .today: return "Today only"
        case .over: return event.earned ? "You did it" : "That's a wrap"
        }
    }

    private var subtitle: String {
        switch event.phase {
        case .upcoming: return "Walk or run a 5K, win the gear"
        case .today:
            return event.earned ? "Gear unlocked" : String(format: "%.2f mi to the gear", event.milesLeft)
        case .over: return event.earned ? "Gear unlocked" : "See you at the next one"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.3)
                .tracking(1)
                .foregroundColor(Color(red: 1, green: 0.72, blue: 0.29))
                .lineLimit(1)
            Text(event.title)
                .madFont(size: compact ? 20 : 26, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if compact {
                Text(subtitle)
                    .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
    }
}

/// Under the ring: days to go, your miles on the day, or the result.
struct SpecialEventStatus: View {
    let event: SpecialEvent

    var body: some View {
        switch event.phase {
        case .upcoming:
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.days_until == 1 ? "Tomorrow" : "\(event.days_until) days")
                        .madFont(size: 22, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                    Text("until \(event.title)")
                        .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                SpecialEventRewardChips(event: event)
            }
        case .today:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", event.my_miles))
                        .madFont(size: 26, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                    Text("of \(String(format: "%.1f", event.miles)) mi")
                        .madFont(size: 14, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer(minLength: 4)
                    Text(event.earned ? "Champ" : "\(Int((event.progress * 100).rounded()))%")
                        .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(event.earned ? .green : Color(red: 1, green: 0.72, blue: 0.29))
                }
                SpecialEventProgressBar(progress: event.progress, done: event.earned)
                if let friends = event.friendsLine {
                    SpecialEventFriendsLine(text: friends)
                }
            }
        case .over:
            VStack(alignment: .leading, spacing: 4) {
                Text(event.earned
                     ? "\(String(format: "%.2f", event.my_miles)) mi · Champ"
                     : "\(String(format: "%.2f", event.my_miles)) mi on the day")
                    .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(event.earned ? .green : .white)
                Text(event.earned
                     ? "Champ Shorts and Boxing Gloves are in your closet."
                     : "The gear was for a 5K on \(event.shortDay).")
                    .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SpecialEventProgressBar: View {
    let progress: Double
    let done: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(done ? AnyShapeStyle(Color.green)
                               : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.94, green: 0.25, blue: 0.36),
                                                                       Color(red: 1, green: 0.62, blue: 0.18)],
                                                              startPoint: .leading, endPoint: .trailing)))
                    .frame(width: max(8, geo.size.width * progress))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

struct SpecialEventFriendsLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.green).frame(width: 7, height: 7)
            Text(text)
                .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// The two pieces of gear, small, for the card's corner.
struct SpecialEventRewardChips: View {
    let event: SpecialEvent

    var body: some View {
        HStack(spacing: 6) {
            ForEach(event.rewardItems, id: \.rawValue) { item in
                FlameyItemArt(item: item, locked: !event.earned, mannequin: false)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.72, green: 0.52, blue: 1).opacity(0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(red: 0.72, green: 0.52, blue: 1).opacity(0.5), lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }
}

enum SpecialEventLook {
    /// Flamey in the event's gear, and nothing else he owns.
    static func wearing(_ event: SpecialEvent) -> FlameyLook {
        let items = event.rewardItems
        var choice = FlameyLookChoice.basic
        for item in items { choice[item.slot] = item }
        return FlameyLook.resolve(owned: Set(items), choice: choice, date: FlameyItemArt.neutralDate, detail: .full)
    }
}

/// The ring: an arena under two spotlights, red/white/blue ropes between two
/// posts, Flamey in the gear in the middle. Live, he's lit for the day, so he
/// throws his gloves up now and then.
struct SpecialEventStage<Caption: View>: View {
    let event: SpecialEvent
    let height: CGFloat
    var live = false
    /// A slim banner: Flamey to the right, words to the left.
    var compact = false
    @ViewBuilder let caption: () -> Caption

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                // The arena.
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.10, green: 0.05, blue: 0.20), location: 0),
                        .init(color: Color(red: 0.24, green: 0.08, blue: 0.30), location: 0.55),
                        .init(color: Color(red: 0.42, green: 0.12, blue: 0.22), location: 1),
                    ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                // Two spotlights.
                let centre = w * (compact ? 0.74 : 0.5)
                for dx in [-0.22, 0.22] {
                    var beam = Path()
                    let top = CGPoint(x: centre + w * dx * 1.6, y: -4)
                    beam.move(to: top)
                    beam.addLine(to: CGPoint(x: centre - w * 0.16 + w * dx * 0.3, y: h))
                    beam.addLine(to: CGPoint(x: centre + w * 0.16 + w * dx * 0.3, y: h))
                    beam.closeSubpath()
                    ctx.fill(beam, with: .linearGradient(
                        Gradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.02)]),
                        startPoint: top, endPoint: CGPoint(x: top.x, y: h)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: centre - w * 0.3, y: h * 0.55, width: w * 0.6, height: h * 0.5)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.7, blue: 0.4).opacity(0.35), .clear]),
                                               center: CGPoint(x: centre, y: h * 0.8), startRadius: 0, endRadius: w * 0.3))
                // The ropes, behind him.
                let floor = h - (compact ? 14 : 46)
                let ropes: [(CGFloat, Color)] = [(0.36, Color(red: 0.93, green: 0.2, blue: 0.3)),
                                                 (0.56, .white), (0.76, Color(red: 0.25, green: 0.45, blue: 0.95))]
                let left = compact ? w * 0.42 : w * 0.06
                let right = compact ? w - 10 : w * 0.94
                for (t, color) in ropes {
                    let y = floor - (floor - h * 0.28) * (1 - t)
                    ctx.fill(Path(roundedRect: CGRect(x: left, y: y - 2, width: right - left, height: 4), cornerRadius: 2),
                             with: .color(color.opacity(0.92)))
                }
                for x in [left, right] {
                    ctx.fill(Path(roundedRect: CGRect(x: x - 4, y: h * 0.26, width: 8, height: floor - h * 0.26), cornerRadius: 3),
                             with: .linearGradient(Gradient(colors: [Color(white: 0.92), Color(white: 0.6)]),
                                                   startPoint: CGPoint(x: x - 4, y: 0), endPoint: CGPoint(x: x + 4, y: 0)))
                }
                // The mat.
                ctx.fill(Path(CGRect(x: 0, y: floor, width: w, height: h - floor)),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.32, green: 0.36, blue: 0.62), Color(red: 0.14, green: 0.14, blue: 0.3)]),
                                               startPoint: CGPoint(x: 0, y: floor), endPoint: CGPoint(x: 0, y: h)))
            }

            FlameBuddyView(health: .blazing, size: height * (compact ? 0.8 : 0.62),
                           mood: FlameMood(kind: .done, streak: 0), still: !live,
                           showsMoodBubble: false, look: SpecialEventLook.wearing(event))
                .frame(maxWidth: .infinity, alignment: compact ? .trailing : .center)
                .padding(.trailing, compact ? 12 : 0)
                .padding(.bottom, compact ? 2 : 34)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .accessibilityHidden(true)

            caption()
                .padding(12)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The event's own page: the ring, what to do, the prize, who's in.
struct SpecialEventView: View {
    let eventId: String?
    private let service = SpecialEventService.shared

    var body: some View {
        ScrollView {
            if let event = service.event(id: eventId) {
                VStack(alignment: .leading, spacing: 16) {
                    SpecialEventStage(event: event, height: 320, live: true) {
                        SpecialEventCaption(event: event)
                    }

                    Text("Walk or run 5K (\(String(format: "%.1f", event.miles)) mi) on \(event.dayLine). Every walk and run that day adds up, in your own time zone. Finish it and the gear is yours to keep.")
                        .madFont(size: 16, weight: .semibold, design: .rounded, maxScale: 1.4)
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    if event.phase != .upcoming {
                        SpecialEventStatus(event: event)
                            .padding(DashboardCardSurface.padding)
                            .background(DashboardCardSurface(style: .fun))
                    }

                    HStack(spacing: 8) {
                        ForEach(event.rewardItems, id: \.rawValue) { item in
                            SpecialEventRewardTile(title: item.displayName, rarity: "Epic",
                                                   color: Color(red: 0.72, green: 0.52, blue: 1), earned: event.earned) {
                                FlameyItemArt(item: item, locked: false, mannequin: false)
                            }
                        }
                        SpecialEventRewardTile(title: "Champ Medal", rarity: "Legendary",
                                               color: Color(red: 1, green: 0.72, blue: 0.29), earned: event.earned) {
                            Image(systemName: "medal.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.5), Color(red: 0.9, green: 0.6, blue: 0.1)],
                                                                startPoint: .top, endPoint: .bottom))
                        }
                    }

                    if let friends = event.friendsLine, event.phase == .upcoming {
                        SpecialEventFriendsLine(text: friends)
                            .padding(DashboardCardSurface.padding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DashboardCardSurface(style: .fun))
                    }
                }
                .padding(16)
            } else {
                Text("This event is over.")
                    .madFont(size: 16, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(40)
            }
        }
        .background(Color(red: 0.08, green: 0.04, blue: 0.06).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.refresh() }
    }
}

struct SpecialEventRewardTile<Art: View>: View {
    let title: String
    let rarity: String
    let color: Color
    let earned: Bool
    @ViewBuilder let art: () -> Art

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                art()
                    .frame(width: 58, height: 58)
                    .frame(maxWidth: .infinity)
                if earned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            Text(title)
                .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(rarity.uppercased())
                .madFont(size: 10, weight: .heavy, design: .rounded, maxScale: 1.3)
                .tracking(0.8)
                .foregroundColor(color)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(RadialGradient(colors: [color.opacity(0.3), color.opacity(0.08)], center: .center, startRadius: 2, endRadius: 56)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(rarity)\(earned ? ", earned" : "")")
    }
}
