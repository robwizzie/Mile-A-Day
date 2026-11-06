import SwiftUI
import UIKit

/// Everything Duo-only asks this one question. Off on every other device, and
/// off on a Duo unless the window is the wide inner "spread": folded, or
/// narrowed in Split View, the app is the ordinary iPhone app.
enum DuoDevice {
    /// Hardware model ids of hinged iPhones. Unknown models read as not-Duo,
    /// so a new device gets the ordinary app until it is added here.
    private static let models: Set<String> = ["iPhone19,4"]

    static let isDuo: Bool = {
        #if DEBUG
        // Test builds only: exercises the layouts on a wide simulator. Compiled
        // out of Release, so no shipped device can reach this.
        if ProcessInfo.processInfo.arguments.contains("-MADDuoPreview") { return true }
        #endif
        return models.contains(modelIdentifier)
    }()

    /// The simulator reports the Mac; its environment names the simulated model.
    private static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Below this the inner display is shared with another app, and two
    /// columns would each be narrower than the smallest iPhone.
    static let spreadMinWidth: CGFloat = 600
}

private struct DuoSpreadKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True only on an iPhone Duo, in a window wide enough for two columns.
    var duoSpread: Bool {
        get { self[DuoSpreadKey.self] }
        set { self[DuoSpreadKey.self] = newValue }
    }
}

private struct DuoColumnWidthKey: EnvironmentKey {
    static let defaultValue = CGFloat.infinity
}

extension EnvironmentValues {
    /// The width of the Duo page this view sits on. Infinite everywhere else.
    var duoColumnWidth: CGFloat {
        get { self[DuoColumnWidthKey.self] }
        set { self[DuoColumnWidthKey.self] = newValue }
    }
}

private struct DuoHomeWideKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while Home has the whole spread to itself (no friends page beside
    /// it), so the dashboard lays out across it instead of down one column.
    var duoHomeWide: Bool {
        get { self[DuoHomeWideKey.self] }
        set { self[DuoHomeWideKey.self] = newValue }
    }
}

private struct DuoSpreadHost: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.duoSpread, width >= DuoDevice.spreadMinWidth)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { width = geo.size.width }
                        .onChange(of: geo.size.width) { _, newWidth in width = newWidth }
                }
            )
    }
}

private struct DuoPageMargins: ViewModifier {
    @Environment(\.duoSpread) private var duoSpread

    func body(content: Content) -> some View {
        // Same modifiers at every width: folding must not rebuild the screen.
        content
            .padding(.top, duoSpread ? 14 : 0)
            .padding(.leading, duoSpread ? 8 : 0)
            .background {
                if duoSpread {
                    MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                }
            }
    }
}

extension View {
    /// Moves a tab's title clear of the inner display's rounded corner, which
    /// has no status bar above it to do that. Off everywhere but the spread.
    func duoPageMargins() -> some View { modifier(DuoPageMargins()) }

    /// Publishes `\.duoSpread` below this view. On every other device this
    /// adds nothing at all: no reader, no state.
    @ViewBuilder
    func duoSpreadHost() -> some View {
        if DuoDevice.isDuo {
            modifier(DuoSpreadHost())
        } else {
            self
        }
    }
}
