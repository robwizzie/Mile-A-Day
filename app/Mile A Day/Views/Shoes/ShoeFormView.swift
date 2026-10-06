import SwiftUI
import UIKit

/// Add or edit a pair, typed in by hand the way Strava's gear works: brand,
/// model, an optional colorway and photo, and its mileage. Shoes are private
/// — only their owner ever sees them.
struct ShoeFormView: View {
    /// nil = adding a new pair.
    let editing: Shoe?
    /// Called with the saved pair before the sheet closes (a workout's picker
    /// gives a pair added from it to that workout).
    let onSaved: ((Shoe) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var store = ShoeStore.shared
    @State private var brand: String
    @State private var model: String
    @State private var colorway: String
    @State private var startingText: String
    /// In the DISPLAY unit; nil = no target.
    @State private var replaceAt: Double?
    /// The activities a NEW pair becomes the default for.
    @State private var defaultFor: Set<ShoeActivity> = []
    @State private var photo: UIImage?
    @State private var showLibrary = false
    @State private var isSaving = false
    @State private var saveError: String?

    init(editing shoe: Shoe? = nil, onSaved: ((Shoe) -> Void)? = nil) {
        self.editing = shoe
        self.onSaved = onSaved
        _brand = State(initialValue: shoe?.brand ?? "")
        _model = State(initialValue: shoe?.name ?? "")
        _colorway = State(initialValue: shoe?.colorway ?? "")
        _startingText = State(initialValue: shoe.map { ShoeUnits.inputText($0.starting_miles) } ?? "")
        let target: Double? = shoe?.replace_at_miles
        _replaceAt = State(initialValue: target.map { ($0 * DistanceUnits.current.perMile).rounded() })
    }

    private var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Says which pair each activity gets today, so ticking a box reads as
    /// replacing it.
    private var defaultsFooter: String {
        let replacing = ShoeActivity.allCases.compactMap { activity -> String? in
            guard defaultFor.contains(activity), let current = store.defaultShoe(for: activity) else { return nil }
            return "\(current.name) for \(activity.noun)"
        }
        let base = "Workouts you do from now on get their default pair automatically. You can change the shoes on any workout from its details."
        return replacing.isEmpty ? base : "Replaces \(replacing.joined(separator: " and ")). " + base
    }

    private var hasPhoto: Bool {
        photo != nil || editing?.image_url != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ShoeThumbnail(url: editing?.imageURL, size: 140, cornerRadius: 18, image: photo)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    Button {
                        showLibrary = true
                    } label: {
                        Label(hasPhoto ? "Change Photo" : "Add a Photo", systemImage: "photo.on.rectangle")
                    }
                } header: {
                    Text("Photo")
                } footer: {
                    Text("Optional — a picture of your pair from your camera roll.")
                }

                Section {
                    ShoeBrandField(brand: $brand)
                    TextField("Model (e.g. Pegasus 41)", text: $model)
                        .textInputAutocapitalization(.words)
                    TextField("Colorway (optional)", text: $colorway)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Shoe")
                } footer: {
                    Text("Only you can see your shoes and their mileage.")
                }

                ShoeMileageFields(startingText: $startingText, replaceAt: $replaceAt)

                if editing == nil {
                    Section {
                        ForEach(ShoeActivity.allCases) { activity in
                            Toggle("Default for \(activity.noun)", isOn: Binding(
                                get: { defaultFor.contains(activity) },
                                set: { on in
                                    if on { defaultFor.insert(activity) } else { defaultFor.remove(activity) }
                                }
                            ))
                            .tint(MADTheme.Colors.success)
                        }
                    } header: {
                        Text("Default")
                    } footer: {
                        Text(defaultsFooter)
                    }
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundColor(MADTheme.Colors.madRed)
                            .font(MADTheme.Typography.caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
            .navigationTitle(editing == nil ? "Add Shoes" : "Edit Shoes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .disabled(trimmedModel.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showLibrary) {
                ImagePicker(selectedImage: $photo, confirmation: .squareCrop)
            }
        }
        .task {
            guard editing == nil else { return }
            await store.refreshIfStale()
            // A first pair is the default for both. After that nothing is
            // ticked: "none for walks" may be a choice, not a gap to fill.
            if store.shoes.isEmpty { defaultFor = Set(ShoeActivity.allCases) }
        }
    }

    private func save() {
        let name = String(trimmedModel.prefix(120))
        guard !name.isEmpty else { return }
        let brandValue = String(brand.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let colorValue = String(colorway.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let starting = min(ShoeUnits.milesFromInput(startingText) ?? 0, 9_999)
        let target: Double? = replaceAt.map { $0 / DistanceUnits.current.perMile }
        let picked = photo

        isSaving = true
        saveError = nil
        Task { @MainActor in
            do {
                let saved: Shoe
                if let editingShoe = editing {
                    let fields: [String: Any] = [
                        "name": name,
                        "brand": brandValue,
                        "colorway": colorValue,
                        "starting_miles": starting,
                        "replace_at_miles": target.map { $0 as Any } ?? (NSNull() as Any),
                    ]
                    try await store.update(editingShoe.shoe_id, fields: fields)
                    if let picked {
                        try await store.replaceImage(picked, shoeId: editingShoe.shoe_id)
                    }
                    saved = store.shoe(id: editingShoe.shoe_id) ?? editingShoe
                } else {
                    var draft = ShoeDraft()
                    draft.name = name
                    draft.brand = brandValue
                    draft.colorway = colorValue
                    draft.startingMiles = starting
                    draft.replaceAtMiles = target
                    draft.defaultFor = defaultFor
                    saved = try await store.add(draft, image: picked).shoe
                }
                isSaving = false
                onSaved?(saved)
                dismiss()
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}

// MARK: - Fields

/// Brand as free text, with the common running brands one tap away.
struct ShoeBrandField: View {
    @Binding var brand: String

    static let commonBrands = [
        "Adidas", "Altra", "ASICS", "Brooks", "HOKA", "Merrell", "Mizuno",
        "New Balance", "Nike", "On", "Puma", "Salomon", "Saucony", "Skechers",
        "Topo Athletic", "Under Armour",
    ]

    var body: some View {
        HStack {
            TextField("Brand", text: $brand)
                .textInputAutocapitalization(.words)
            Menu {
                ForEach(Self.commonBrands, id: \.self) { name in
                    Button(name) { brand = name }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Choose a brand")
        }
    }
}

/// "Already on them" + "Replace at", in the user's display unit.
struct ShoeMileageFields: View {
    @Binding var startingText: String
    /// Display unit; nil = no target.
    @Binding var replaceAt: Double?

    private var unit: String { DistanceUnits.current.abbreviation }

    /// The presets, plus the current value when it isn't one of them (a
    /// target set before the user switched units).
    private var options: [Double] {
        var values = ShoeUnits.replacePresets
        if let replaceAt, !values.contains(replaceAt) {
            values.append(replaceAt)
            values.sort()
        }
        return values
    }

    var body: some View {
        Section {
            HStack {
                Text("Already on them")
                Spacer()
                TextField("0", text: $startingText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                Text(unit)
                    .foregroundColor(.secondary)
            }

            Picker("Replace at", selection: $replaceAt) {
                Text("No target").tag(Double?.none)
                ForEach(options, id: \.self) { value in
                    Text("\(Int(value.rounded())) \(unit)").tag(Double?.some(value))
                }
            }
        } header: {
            Text("Mileage")
        } footer: {
            Text("A pair's mileage is the walks and runs you give it, plus anything it had before you started tracking. Most running shoes are replaced somewhere around 300–500 miles.")
        }
    }
}
