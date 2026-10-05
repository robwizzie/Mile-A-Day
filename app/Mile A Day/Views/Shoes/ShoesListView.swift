import SwiftUI

/// Every pair the user tracks: in rotation first (default on top), retired
/// below. Pushed from Settings and from the profile's Shoes card.
struct ShoesListView: View {
    @State private var store = ShoeStore.shared
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                if !store.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, MADTheme.Spacing.xl)
                } else if store.shoes.isEmpty {
                    emptyState
                } else {
                    section("IN ROTATION", shoes: store.active)
                    if !store.retired.isEmpty {
                        section("RETIRED", shoes: store.retired)
                    }
                    Text("Only you can see your shoes and their mileage.")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(MADTheme.Spacing.md)
            .lockedToScrollWidth()
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .navigationTitle("Shoes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add shoes")
            }
        }
        .sheet(isPresented: $showAdd) {
            ShoeFormView()
        }
        .refreshable { await store.refresh() }
        .task { await store.refreshIfStale(maxAge: 5) }
    }

    @ViewBuilder
    private func section(_ title: String, shoes: [Shoe]) -> some View {
        if !shoes.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                ProfileCardLabel(text: title)
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(shoes.enumerated()), id: \.element.id) { index, shoe in
                        if index > 0 {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                        NavigationLink {
                            ShoeDetailView(shoeId: shoe.shoe_id)
                        } label: {
                            ShoeRow(shoe: shoe)
                                .padding(.vertical, MADTheme.Spacing.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, MADTheme.Spacing.xs)
                .madLiquidGlass()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: ShoeSymbol.filled)
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
                .accessibilityHidden(true)
            Text("Track your shoes")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
            Text(store.loadFailed
                 ? "Couldn't load your shoes. Pull down to try again."
                 : "Paste a link to your pair and every walk and run adds to its mileage — so you know when it's time for a new one.")
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button {
                showAdd = true
            } label: {
                Label("Add Shoes", systemImage: "plus")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(MADTheme.Colors.madRed))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.xl)
        .padding(.horizontal, MADTheme.Spacing.md)
        .madLiquidGlass()
    }
}
