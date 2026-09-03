//
//  ScrollAxisLock.swift
//  Mile A Day
//
//  Stops a vertical ScrollView from scrolling sideways.
//

import SwiftUI

extension View {
    /// Pins this scroll content to exactly the scroll view's width, so the
    /// scroll view can only ever move on one axis.
    ///
    /// A SwiftUI `ScrollView` is a UIScrollView, and it scrolls on whichever
    /// axis its CONTENT overflows — the `.vertical` axis argument governs
    /// bouncing, not scrolling. So a single subview a few points too wide makes
    /// the whole page pannable sideways, and because a UIScrollView rubber-bands
    /// well past its content, a few points of overflow become a hundred points
    /// of travel. Every vertical drag then picks up a horizontal component: the
    /// page visibly wobbles and slides out from under the nav bar.
    ///
    /// The overflow itself is easy to reintroduce and hard to see coming — this
    /// app has hit it repeatedly, always from a label whose width is DATA (a
    /// username, a third-party app name, a date range) sitting next to a
    /// `.fixedSize()` chip that publishes a minimum width no ancestor can shrink
    /// (see ios.md). Fixing each atom fixes one instance; locking the axis means
    /// the next one can't produce this symptom at all.
    ///
    /// An oversized child is then centred and clipped, which is exactly what a
    /// ScrollView already does with content it can't fit — so this changes
    /// nothing for the full-width card layouts it's applied to, and it is NOT a
    /// licence to stop fixing the overflow: a clipped row is still a bug, just a
    /// quieter and more honest one than a screen that shakes.
    ///
    /// Apply to the CONTENT inside the ScrollView, outside its own padding —
    /// never to the ScrollView itself, which is already the right width.
    func lockedToScrollWidth() -> some View {
        containerRelativeFrame(.horizontal)
    }
}
