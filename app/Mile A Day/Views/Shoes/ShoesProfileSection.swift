import SwiftUI

/// The Shoes card on the OWN profile's Stats tab — the pairs in rotation and
/// their mileage. Never placed on `UserProfileDetailView`: shoes are private,
/// and the endpoint behind this is self-only anyway.
struct ShoesProfileSection: View {
    @State private var store = ShoeStore.shared
    @State private var showAdd = false

    /// The card stays short; the full list is a tap away.
    private let maxRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            header

            if !store.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MADTheme.Spacing.md)
            } else if store.active.isEmpty {
                emptyState
            } else {
                VStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(store.active.prefix(maxRows)) { shoe in
                        NavigationLink {
                            ShoeDetailView(shoeId: shoe.shoe_id)
                        } label: {
                            ShoeRow(shoe: shoe, thumbnailSize: 50)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
        .sheet(isPresented: $showAdd) {
            ShoeFormView()
        }
        .task { await store.refreshIfStale() }
    }

    private var header: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: ShoeSymbol.filled)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.madWhite)
                .accessibilityHidden(true)
            Text("Shoes")
                .font(MADTheme.Typography.headline)
                .foregroundStyle(MADTheme.Colors.madWhite)
            Spacer()
            if !store.shoes.isEmpty {
                NavigationLink {
                    ShoesListView()
                } label: {
                    HStack(spacing: 3) {
                        Text(store.shoes.count > maxRows || !store.retired.isEmpty ? "All \(store.shoes.count)" : "Manage")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            Text(store.loadFailed
                 ? "Couldn't load your shoes."
                 : store.shoes.isEmpty
                    ? "Add your shoes and every walk and run in them adds to their mileage. Only you can see them."
                    : "Every pair is retired. Add your new ones.")
                .font(MADTheme.Typography.caption)
                .foregroundStyle(MADTheme.Colors.madWhite.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showAdd = true
            } label: {
                Label("Add Shoes", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(MADTheme.Colors.madRed))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
    }
}
