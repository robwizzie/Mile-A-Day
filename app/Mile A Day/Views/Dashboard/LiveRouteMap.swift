import SwiftUI
import MapKit

/// The line you've walked so far, following you, plus the line of anyone on the
/// walk who chose to share theirs while you share yours. Sharing is off until
/// you turn it on, every walk (`BuddyLiveRouteSharing`).
struct LiveRouteMap: View {
    /// This walk, for the share control and the friends' names.
    var session: BuddySessionState? = nil

    /// Close enough to read the next few blocks at a glance mid-walk.
    private var followDistance: CLLocationDistance { 1_100 }
    /// Friends further apart than this are walking somewhere else: the map
    /// stays on you rather than zooming out to a whole city.
    private let togetherMeters = 4_000.0
    private static let friendColors: [Color] = [.cyan, .yellow, .mint, .orange, .purple, .pink, .white]

    @ObservedObject private var sharing = BuddyLiveRouteSharing.shared
    @State private var trail: [CLLocationCoordinate2D] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var askingToShare = false
    @State private var shareBlocked = false
    @State private var isChanging = false

    /// Stealth and maps-off mean this walker has said no already, so the choice
    /// isn't offered at all. The server enforces the same rules regardless.
    private var canOfferSharing: Bool {
        session != nil && !StealthModeStore.shared.isOn
            && NotificationPreferences.load().shareRouteMaps
    }

    private var holdbackText: String {
        (BuddyLiveRouteSharing.holdbackMeters / 1_609.34).distanceFormatted
    }

    private func firstName(of userId: String) -> String {
        let person = session?.participants.first { $0.userId == userId }
        return person?.firstName ?? person?.username ?? "Friend"
    }

    private func color(at index: Int) -> Color {
        Self.friendColors[index % Self.friendColors.count]
    }

    var body: some View {
        ZStack {
            if let here = trail.last {
                Map(position: $position, interactionModes: []) {
                    ForEach(Array(sharing.friendRoutes.enumerated()), id: \.element.id) { index, route in
                        if route.coordinates.count > 1 {
                            MapPolyline(coordinates: route.coordinates)
                                .stroke(color(at: index),
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        }
                        if let head = route.coordinates.last {
                            Annotation(firstName(of: route.userId), coordinate: head) {
                                Text(firstName(of: route.userId))
                                    .madFont(size: 11, weight: .bold, design: .rounded, maxScale: 1.2)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(color(at: index)))
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                    if trail.count > 1 {
                        MapPolyline(coordinates: trail)
                            .stroke(MADTheme.Colors.madRed,
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    }
                    Annotation("You", coordinate: here) {
                        Circle()
                            .fill(MADTheme.Colors.madRed)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    }
                    .annotationTitles(.hidden)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            } else {
                // Never the map's own fallback: with no fix it shows a
                // whole continent.
                VStack(spacing: 10) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.system(size: 30, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Finding your route")
                        .madFont(size: 15, weight: .semibold, design: .rounded, maxScale: 1.3)
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.22))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if canOfferSharing { shareButton.padding(10) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your live route")
        .alert("Share your route on this walk?", isPresented: $askingToShare) {
            Button("Share route") { change(to: true) }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Only people on this walk who also share can see your line, and you'll see theirs. Friends who aren't on this walk can't, even if they see you're out. Your line stays \(holdbackText) behind you, so where you start and finish stay hidden. It's deleted when the walk ends.")
        }
        .alert("Route sharing is off", isPresented: $shareBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Stealth Mode, private workouts or Show route maps in Privacy settings are keeping your route to yourself.")
        }
        .task(id: session?.id) {
            if let id = session?.id { await sharing.attach(sessionId: id) }
        }
        .onChange(of: sharing.friendRoutes) { recenter(animated: true) }
        .task {
            // A slow poll, not a publisher: one fix a second must never
            // redraw the tracker around this map.
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var shareButton: some View {
        Button {
            MADHaptics.tap()
            if sharing.isSharing { change(to: false) } else { askingToShare = true }
        } label: {
            Label(sharing.isSharing ? "Sharing route" : "Share route",
                  systemImage: sharing.isSharing ? "person.2.fill" : "person.2")
                .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.2)
                .lineLimit(1)
                .foregroundColor(sharing.isSharing ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(sharing.isSharing ? Color.white : Color.black.opacity(0.65)))
        }
        .buttonStyle(.plain)
        .disabled(isChanging)
        .accessibilityHint(sharing.isSharing ? "Stops sharing and removes your line" : "Asks before sharing")
    }

    private func change(to enabled: Bool) {
        isChanging = true
        Task {
            defer { isChanging = false }
            do {
                try await sharing.setSharing(enabled)
            } catch {
                if enabled { shareBlocked = true }
            }
        }
    }

    private func refresh() {
        let latest = WorkoutLocationManager.shared.liveTrail
        guard latest.count != trail.count, latest.last != nil else { return }
        trail = latest
        recenter(animated: true)
    }

    /// Everyone in frame while you're walking together; otherwise just you.
    private func recenter(animated: Bool) {
        guard let here = trail.last else { return }
        let target = togetherRect(around: here).map(MapCameraPosition.rect)
            ?? .camera(MapCamera(centerCoordinate: here, distance: followDistance))
        withAnimation(animated ? .easeInOut(duration: 1) : nil) { position = target }
    }

    private func togetherRect(around here: CLLocationCoordinate2D) -> MKMapRect? {
        let heads = sharing.friendRoutes.compactMap(\.coordinates.last)
        guard !heads.isEmpty else { return nil }
        let you = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let near = heads.filter {
            you.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < togetherMeters
        }
        guard !near.isEmpty else { return nil }
        let points = (trail + sharing.friendRoutes.flatMap(\.coordinates)).map(MKMapPoint.init)
        var rect = MKMapRect.null
        for point in points {
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        return rect.insetBy(dx: -rect.width * 0.2 - 200, dy: -rect.height * 0.2 - 200)
    }
}
