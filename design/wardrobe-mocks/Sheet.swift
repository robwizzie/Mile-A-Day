import SwiftUI
import AppKit

let madRed = Color(red: 0.85, green: 0.25, blue: 0.35)
let ember = Color(red: 1.0, green: 0.72, blue: 0.35)

struct SheetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.15, green: 0.08, blue: 0.10), Color(red: 0.09, green: 0.045, blue: 0.055), Color(red: 0.05, green: 0.02, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.orange.opacity(0.13), .clear], center: UnitPoint(x: 0.2, y: 0.05), startRadius: 0, endRadius: 700)
            RadialGradient(colors: [madRed.opacity(0.12), .clear], center: UnitPoint(x: 0.9, y: 0.6), startRadius: 0, endRadius: 800)
        }
    }
}

struct SheetHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1.6).foregroundColor(ember)
            Text(title)
                .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionLabel: View {
    let text: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(text.uppercased()).font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1.3).foregroundColor(.white.opacity(0.85))
            if !detail.isEmpty { Text(detail).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.4)) }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }
}

/// The admin/app card: 16pt corners, 5% fill, 8% hairline.
struct Card<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    var glow: Color = .orange
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack { content() }
            .frame(width: width, height: height)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.045))
                    RadialGradient(colors: [glow.opacity(0.16), .clear], center: UnitPoint(x: 0.5, y: 0.55), startRadius: 0, endRadius: width * 0.6)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                })
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Caption: View {
    let title: String
    let sub: String
    var titleSize: CGFloat = 14
    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: titleSize, weight: .heavy, design: .rounded)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.system(size: titleSize - 3, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.5)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// A Flamey standing on a small stage floor inside a card.
struct FlameyCell: View {
    var flamey: Flamey
    var title: String
    var sub: String
    var width: CGFloat = 200
    var height: CGFloat = 250
    var glow: Color = .orange
    var flameyY: CGFloat = 0
    var flameyX: CGFloat = 0
    var body: some View {
        Card(width: width, height: height, glow: glow) {
            VStack(spacing: 0) {
                ZStack {
                    Ellipse().fill(RadialGradient(colors: [Color.white.opacity(0.07), .clear], center: .center, startRadius: 0, endRadius: flamey.size * 0.5))
                        .frame(width: flamey.size * 1.0, height: flamey.size * 0.2)
                        .offset(y: flamey.size * 0.5)
                    flamey
                }
                .offset(x: flameyX)
                .frame(width: width, height: height - 52)
                .offset(y: flameyY)
                Caption(title: title, sub: sub)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                Spacer(minLength: 0)
            }
        }
    }
}

@MainActor
func renderPNG<V: View>(_ view: V, _ path: String, scale: CGFloat = 2) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let cg = renderer.cgImage else { print("render failed", path); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { print("png failed"); return }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote", path, cg.width, "x", cg.height)
}

func grid<T, V: View>(_ items: [T], cols: Int, spacing: CGFloat = 14, @ViewBuilder cell: @escaping (T) -> V) -> some View {
    let rows = (items.count + cols - 1) / cols
    return VStack(alignment: .leading, spacing: spacing) {
        ForEach(0..<rows, id: \.self) { r in
            HStack(spacing: spacing) {
                ForEach(0..<cols, id: \.self) { c in
                    let i = r * cols + c
                    if i < items.count { cell(items[i]) }
                }
            }
        }
    }
}
