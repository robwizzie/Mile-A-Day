import SwiftUI
import UIKit

// Shared pieces of the shoe tracker. Shoes are private to their owner: none
// of these views is ever placed on a friend's profile, a post or the feed.

// MARK: - Symbol

enum ShoeSymbol {
    /// `shoe.fill` where the OS has it (ios.md: a symbol newer than the
    /// deployment target draws a BLANK box rather than falling back).
    static let filled: String = UIImage(systemName: "shoe.fill") != nil ? "shoe.fill" : "figure.walk"
    static let outline: String = UIImage(systemName: "shoe") != nil ? "shoe" : "figure.walk"
}

// MARK: - Units

enum ShoeUnits {
    /// "312 mi" / "502 km" — whole units: a pair's mileage is a wear gauge,
    /// and a decimal on it reads as false precision.
    static func whole(_ miles: Double) -> String {
        let value = Int((miles.inDisplayUnit).rounded(.down))
        return "\(value) \(DistanceUnits.current.abbreviation)"
    }

    /// A number typed in the DISPLAY unit, as miles. Accepts "," decimals.
    static func milesFromInput(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0, value.isFinite else { return nil }
        return value / DistanceUnits.current.perMile
    }

    /// Miles shown in the display unit for an input field ("" for zero).
    static func inputText(_ miles: Double) -> String {
        guard miles > 0 else { return "" }
        let value = miles.inDisplayUnit
        return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Typical "replace at" mileages, in the display unit.
    static var replacePresets: [Double] {
        DistanceUnits.current == .kilometers
            ? [400, 500, 600, 700, 800]
            : [250, 300, 350, 400, 450, 500]
    }
}

// MARK: - Thumbnail

/// A shoe's photo filling a rounded tile, with a glyph when there is none. Backed by `FeedImageCache` so a list doesn't
/// re-download on every scroll pass.
struct ShoeThumbnail: View {
    let url: URL?
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 12
    /// A just-picked picture not yet uploaded (the add flow).
    var image: UIImage? = nil

    @State private var loaded: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))
            if let shown = image ?? loaded {
                // The owner's own photo of the pair: fill the tile, never
                // letterbox it.
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Image(systemName: ShoeSymbol.filled)
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) { await load() }
    }

    private func load() async {
        guard image == nil, let url else {
            loaded = nil
            return
        }
        if let cached = FeedImageCache.image(for: url) {
            loaded = cached
            return
        }
        guard let result = try? await URLSession.shared.data(from: url),
              let decoded = UIImage(data: result.0) else { return }
        FeedImageCache.store(decoded, for: url)
        loaded = decoded
    }
}

// MARK: - Wear bar

/// Mileage against the pair's "replace at" target. Green while there's life
/// left, amber in the last 15%, red once past it.
struct ShoeWearBar: View {
    let fraction: Double

    private var tint: Color {
        if fraction >= 1 { return MADTheme.Colors.madRed }
        if fraction >= 0.85 { return MADTheme.Colors.warning }
        return MADTheme.Colors.success
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent of replacement mileage")
    }
}

// MARK: - Row

/// One pair: picture, name, brand · colourway, mileage, and the wear bar
/// when a replace-at target is set.
struct ShoeRow: View {
    let shoe: Shoe
    var thumbnailSize: CGFloat = 56

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ShoeThumbnail(url: shoe.imageURL, size: thumbnailSize)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(shoe.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if shoe.is_default {
                        ShoeDefaultChip()
                    }
                }
                if let detail = shoe.detailLine {
                    Text(detail)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                if let wear = shoe.wearFraction {
                    ShoeWearBar(fraction: wear)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ShoeUnits.whole(shoe.total_miles))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                if let target = shoe.replace_at_miles {
                    Text("of \(ShoeUnits.whole(target))")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// The small "DEFAULT" tag beside the pair new workouts get.
struct ShoeDefaultChip: View {
    var body: some View {
        Text("DEFAULT")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundColor(MADTheme.Colors.success)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(MADTheme.Colors.success.opacity(0.15)))
            .lineLimit(1)
            .fixedSize()
    }
}
