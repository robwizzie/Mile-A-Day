import Foundation

extension FlameyFacts {
    /// The user's OWN Flamey whatever the dashboard style is right now.
    ///
    /// `look()` is nil on Modern, which is right for every live surface —
    /// but the style pickers (the chooser, Customize's Look tiles) show the
    /// Fun mascot TO a Modern user precisely so they can pick him, and a
    /// plain stand-in there is a Flamey they've never met: the one they
    /// dressed in the Closet is the one they should recognise.
    @MainActor
    static func ownLook(mood: FlameMood.Kind? = nil, date: Date = Date(),
                        detail: FlameyRenderDetail = .full) -> FlameyLook {
        let props = mood.map { FlameMood(kind: $0, streak: 0).props } ?? []
        return FlameyLook.resolve(owned: ownedItems, choice: choice, date: date, mood: props,
                                  signupDate: signupDate, detail: detail)
    }
}
