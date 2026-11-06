import SwiftUI

/// The only file that names the hinge API, so a toolchain older than the
/// iOS 27.1 SDK (CI's default Xcode can lag) still type-checks the app. The
/// App Store build needs Xcode 27.2+ or this compiles to nothing.
private struct DuoHingeObserver: ViewModifier {
    let onOpen: () -> Void
    let onClose: () -> Void

    func body(content: Content) -> some View {
        #if compiler(>=6.4.2)
        if #available(iOS 27.1, *) {
            content.onHingeChange(isEnabled: DuoDevice.isDuo) { old, new in
                guard let before = old.hinge?.status, let after = new.hinge?.status else { return }
                if before == .closed, after != .closed {
                    onOpen()
                } else if before != .closed, after == .closed {
                    onClose()
                }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func onDuoHinge(open: @escaping () -> Void, close: @escaping () -> Void) -> some View {
        modifier(DuoHingeObserver(onOpen: open, onClose: close))
    }
}
