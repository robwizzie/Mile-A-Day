import SwiftUI

// FLAMEY'S CLOSET ↔ THE MEDALS SCREEN. A medal that unlocks something for
// Flamey says so where the medal is (Fun only — Modern never hears of him):
// a small item glyph on its tile in the medal grid, and in its detail an
// "Unlocks for Flamey" card with the item and a "See it in Flamey's Closet"
// button that opens the Closet ON that item, its card up. The Closet says the
// same thing from the other side (the medal on every tile), so the link reads
// both ways. The pieces here are pure (the macOS harness renders them); the
// `…Live` wrappers (FlameyClosetLive.swift) read the style and present the Closet.

// MARK: - The glyph on a medal tile

/// A little disc with the item on it, hung off a medal's corner — "this
/// medal dresses Flamey". Greyed until the medal is earned.
struct FlameyMedalItemGlyph: View {
    let items: [FlameyItem]
    var earned: Bool
    var size: CGFloat = 34

    var body: some View {
        if let first = items.first {
            ZStack {
                Circle().fill(Color(red: 0.13, green: 0.06, blue: 0.08))
                FlameyItemArt(item: first, locked: !earned)
                    .frame(width: size * 0.92, height: size * 0.82)
                    .clipShape(Circle())
                Circle().strokeBorder(earned ? FlameyClosetStyle.ember.opacity(0.85) : Color.white.opacity(0.22),
                                      lineWidth: 1.5)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if items.count > 1 {
                    Text("+\(items.count - 1)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(FlameyClosetStyle.ember))
                        .offset(x: 5, y: -3)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(FlameyMedalLink.spokenList(items, earned: earned))
        }
    }
}

extension FlameyMedalLink {
    /// "Unlocks Rocket Boots for Flamey" / "Will unlock … for Flamey".
    static func spokenList(_ items: [FlameyItem], earned: Bool) -> String {
        let names = items.map(\.displayName)
        let list = names.count <= 2 ? names.joined(separator: " and ")
            : names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        return (earned ? "Unlocks " : "Will unlock ") + list + " for Flamey"
    }
}

// MARK: - The card in a medal's detail

/// "Unlocks for Flamey" (earned) / "Will unlock for Flamey" (locked): the
/// item as he'd wear it, its name and slot, and the way into the Closet.
struct FlameyMedalUnlockCard: View {
    let items: [FlameyItem]
    var earned: Bool
    var onOpen: (FlameyItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "hanger")
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
                Text(earned ? "UNLOCKS FOR FLAMEY" : "WILL UNLOCK FOR FLAMEY")
                    .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1.1)
            }
            .foregroundColor(FlameyClosetStyle.ember)
            .accessibilityAddTraits(.isHeader)
            ForEach(items, id: \.self) { item in
                HStack(spacing: 12) {
                    // In full colour even when locked: this is the preview
                    // of what the medal will get you.
                    FlameyItemArt(item: item)
                        .frame(width: 64, height: 54)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FlameyClosetStyle.artFill))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .madFont(size: 16, weight: .heavy, design: .rounded)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(earned ? "\(item.slot.pickLabel) · in his closet" : "\(item.slot.pickLabel) · earn this medal to wear it")
                            .madFont(size: 12.5, weight: .semibold, design: .rounded)
                            .foregroundColor(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            if let first = items.first {
                Button {
                    MADHaptics.action()
                    onOpen(first)
                } label: {
                    HStack(spacing: 6) {
                        Text("See it in Flamey's Closet")
                            .madFont(size: 15, weight: .heavy, design: .rounded, maxScale: 1.4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .heavy))
                            .accessibilityHidden(true)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FlameyClosetStyle.primaryFill))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Flamey's Closet on \(first.displayName)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(FlameyClosetStyle.ember.opacity(0.25), lineWidth: 1))
    }
}
