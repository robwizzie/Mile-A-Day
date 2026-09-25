import SwiftUI

// FLAMEY'S CLOSET — saving, outfits, his name, and HOW a medal was earned.
// Every piece here is pure (the macOS harness renders them from stub data):
// the model carries the callbacks, `FlameyClosetLive.swift` wires them.
//
// THE SAVE MODEL: the Closet is an editing session. Taps change a DRAFT on
// the stage; the moment it differs from what he wears, `FlameySaveBar`
// docks at the bottom ("Unsaved changes · Discard · Save"), and leaving
// with a draft raises `FlameyLeavePromptCard` ("Save changes to Sparky's
// look?" Save / Discard / Keep editing). Outfits load INTO the draft too, so
// there is one rule for everything: nothing he wears changes until Save.

// MARK: - Small shared bits

/// A workout id to open (`.sheet(item:)`).
struct FlameyWorkoutRef: Identifiable, Hashable {
    let id: String
}

/// A text field the harness can photograph: ImageRenderer draws no AppKit
/// field, so a `still` render prints the value (or the placeholder) instead.
struct FlameyTextField: View {
    let placeholder: String
    @Binding var text: String
    var maxLength: Int
    var still: Bool = false
    var isError: Bool = false
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if still {
                    Text(text.isEmpty ? placeholder : text)
                        .foregroundColor(text.isEmpty ? .white.opacity(0.35) : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.35)))
                        .foregroundColor(.white)
                        .submitLabel(submitLabel)
                        .onSubmit(onSubmit)
                        .autocorrectionDisabled()
                }
            }
            .madFont(size: 18, weight: .heavy, design: .rounded, maxScale: 1.4)
            .lineLimit(1)
            Text("\(FlameyNameRules.normalize(text).count)/\(maxLength)")
                .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.3, monospacedDigit: true)
                .foregroundColor(FlameyNameRules.normalize(text).count > maxLength ? FlameyClosetStyle.newDot : .white.opacity(0.4))
                .fixedSize()
                .accessibilityLabel("\(FlameyNameRules.normalize(text).count) of \(maxLength) characters")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(isError ? FlameyClosetStyle.newDot.opacity(0.8) : Color.white.opacity(0.14), lineWidth: isError ? 1.5 : 1))
    }
}

/// The line under a name field: the problem, or the rule.
struct FlameyFieldNote: View {
    var error: String?
    var hint: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: error == nil ? "info.circle" : "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .accessibilityHidden(true)
            Text(error ?? hint)
                .madFont(size: 12.5, weight: .semibold, design: .rounded, maxScale: 1.3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(error == nil ? .white.opacity(0.45) : FlameyClosetStyle.newDot)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A sheet's scrolling body — drawn flat, top-aligned, for a still render
/// (ImageRenderer can't see into a ScrollView).
struct FlameySheetScroll<Content: View>: View {
    var still: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if still {
            content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { content() }
                .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// A full-width button in the Closet's two weights.
struct FlameyWideButton: View {
    let title: String
    var icon: String? = nil
    var filled: Bool = true
    var busy: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(.white).controlSize(.small)
                } else if let icon {
                    Image(systemName: icon)
                        .madFont(size: 15, weight: .bold, maxScale: 1.3)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(.white.opacity(enabled ? 1 : 0.45))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                if filled && enabled {
                    shape.fill(FlameyClosetStyle.primaryFill)
                } else {
                    shape.fill(Color.white.opacity(0.09)).overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

/// A plain text button ("Cancel", "Keep editing").
struct FlameyTextButton: View {
    let title: String
    var tint: Color = .white.opacity(0.7)
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.4)
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - How a medal was earned

/// "HOW YOU EARNED IT · You ran a 7:42 mile · Aug 14, 2026 · View workout" —
/// the server's `earned_detail`, shown wherever an earned medal is explained
/// (the Closet's item card, the medal's own detail). Without it (an older
/// server): "EARNED FOR · Run a mile under 8:00 · Earned Aug 14, 2026" —
/// never just a name and a date.
struct FlameyHowEarned: View {
    let medal: FlameyMedalInfo
    /// The medal's requirement, in words — the fallback.
    let requirement: String
    /// nil = no link (no workout, or nowhere to open one from here).
    var onViewWorkout: ((String) -> Void)? = nil

    var body: some View {
        let how = FlameyClosetCopy.howEarned(medal, requirement: requirement)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
                Text(how.isDetail ? "HOW YOU EARNED IT" : "EARNED FOR")
                    .madFont(size: 10.5, weight: .black, design: .rounded, maxScale: 1.3)
                    .tracking(1)
            }
            .foregroundColor(FlameyClosetStyle.worn)
            VStack(alignment: .leading, spacing: 2) {
                Text(how.text)
                    .madFont(size: how.isDetail ? 18 : 15, weight: how.isDetail ? .heavy : .bold, design: .rounded)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = medal.earnedDate {
                    Text(how.isDetail ? FlameyClosetCopy.day(date) : "Earned \(FlameyClosetCopy.day(date))")
                        .madFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .accessibilityElement(children: .combine)
            if let id = medal.earnedWorkoutId, let onViewWorkout {
                Button {
                    onViewWorkout(id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 12, weight: .bold))
                            .accessibilityHidden(true)
                        Text("View workout")
                            .madFont(size: 13.5, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .lineLimit(1)
                            .fixedSize()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .heavy))
                            .accessibilityHidden(true)
                    }
                    .foregroundColor(FlameyClosetStyle.ember)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(FlameyClosetStyle.ember.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(FlameyClosetStyle.ember.opacity(0.3), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the workout that earned this medal")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The save bar

/// Docked at the bottom of the Closet while the draft isn't saved. It also
/// carries the last change and its Undo (the separate toast would stack a
/// second bar over the grid — on an SE the two covered it).
struct FlameySaveBar: View {
    let changes: Int
    let possessiveName: String
    /// The last change ("Trying on Bow Tie"), while it's fresh.
    var note: String? = nil
    /// Steps the draft back one change; nil = nothing to undo.
    var onUndo: (() -> Void)? = nil
    var onDiscard: () -> Void
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Circle().fill(FlameyClosetStyle.ember).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text("Not saved")
                        .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                }
                Text(note ?? (changes == 1 ? "1 change to \(possessiveName) look" : "\(changes) changes to \(possessiveName) look"))
                    .madFont(size: 11.5, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.55))
                    .id(note)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let onUndo {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .madFont(size: 14, weight: .bold, maxScale: 1.3)
                        .foregroundColor(FlameyClosetStyle.ember)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo")
                .accessibilityHint("Takes back the last change")
            }
            Button(action: onDiscard) {
                Text("Discard")
                    .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Puts back the look he's wearing")
            Button(action: onSave) {
                Text("Save")
                    .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 22)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(FlameyClosetStyle.primaryFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("He wears this look everywhere")
        }
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.13, green: 0.07, blue: 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(FlameyClosetStyle.ember.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }
}

// MARK: - "Save changes?"

/// Leaving with an unsaved draft: what he wears now beside what he'd wear,
/// and the three answers. Drawn by the Closet itself (not an alert), so it
/// can show the two looks and the harness can photograph it.
struct FlameyLeavePromptCard: View {
    let name: String
    let saved: FlameyLook
    let draft: FlameyLook
    let changes: Int
    var onAnswer: (FlameyLeavePrompt.Answer) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onAnswer(.keepEditing) }
                .accessibilityHidden(true)
            VStack(spacing: 16) {
                HStack(alignment: .bottom, spacing: 18) {
                    figure(saved, caption: "Now", dim: true)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 34)
                        .accessibilityHidden(true)
                    figure(draft, caption: "New look", dim: false)
                }
                .padding(.top, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("His look now, and the new look")
                VStack(spacing: 6) {
                    Text("Save changes to \(FlameyNameRules.possessive(name)) look?")
                        .madFont(size: 21, weight: .black, design: .rounded)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(changes == 1
                         ? "You changed 1 thing. Save to wear it everywhere, or discard to put back what he had on."
                         : "You changed \(changes) things. Save to wear them everywhere, or discard to put back what he had on.")
                        .madFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    FlameyWideButton(title: "Save", icon: "checkmark") { onAnswer(.save) }
                    FlameyWideButton(title: "Discard changes", filled: false) { onAnswer(.discard) }
                    FlameyTextButton(title: "Keep editing") { onAnswer(.keepEditing) }
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(red: 0.11, green: 0.05, blue: 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func figure(_ look: FlameyLook, caption: String, dim: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                Ellipse().fill(Color.white.opacity(0.07)).frame(width: 70, height: 10).offset(y: 3)
                FlameyDressedFigure(look: look, health: .healthy, size: 64, scale: 1)
                    .frame(width: 64, height: 64)
            }
            .frame(width: 92, height: 88, alignment: .bottom)
            .opacity(dim ? 0.55 : 1)
            Text(caption.uppercased())
                .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.2)
                .tracking(1)
                .foregroundColor(dim ? .white.opacity(0.45) : FlameyClosetStyle.ember)
        }
    }
}

// MARK: - Outfits row

/// Saved outfits under the stage: a chip each (a tiny him in it + its name)
/// that loads it into the draft — Save wears it, like any other change —
/// then "Save as outfit" (or, with five saved, "Replace an outfit") and
/// Edit. An outfit naming something no longer owned wears a warning dot and
/// is worn without it.
struct FlameyOutfitsRow: View {
    let model: FlameyClosetModel
    var scrollable: Bool = true
    var onSaveAs: () -> Void
    var onManage: () -> Void

    var body: some View {
        let row = HStack(spacing: 6) {
            if model.outfits.isEmpty {
                Text("OUTFITS")
                    .madFont(size: 10.5, weight: .black, design: .rounded, maxScale: 1.2)
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize()
                    .padding(.trailing, 2)
                    .accessibilityHidden(true)
            }
            ForEach(model.outfits) { outfit in
                chip(outfit)
            }
            saveChip
            if !model.outfits.isEmpty {
                Button(action: onManage) {
                    Image(systemName: "slider.horizontal.3")
                        .madFont(size: 13, weight: .bold, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit outfits")
                .accessibilityHint("Rename, reorder or delete your saved outfits")
            }
        }
        .padding(.horizontal, 16)
        Group {
            if scrollable {
                ScrollView(.horizontal) { row }
                    .scrollIndicators(.hidden)
            } else {
                Color.clear.overlay(alignment: .leading) { row.fixedSize() }.clipped()
            }
        }
        .frame(height: 42)
    }

    private func chip(_ outfit: FlameyOutfit) -> some View {
        let current = model.currentOutfit?.id == outfit.id
        let unavailable = model.hasUnavailable(outfit)
        return Button {
            MADHaptics.tap()
            withAnimation(.snappy) { model.tryOn(outfit) }
        } label: {
            HStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    Circle().fill(Color.white.opacity(0.07))
                    FlameyDressedFigure(look: model.look(for: model.wearable(outfit), detail: .compact),
                                        health: .healthy, size: 26, scale: 1)
                        .frame(width: 26, height: 26)
                        .padding(.bottom, 2)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if unavailable {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 7, weight: .black))
                            .foregroundColor(.black)
                            .frame(width: 13, height: 13)
                            .background(Circle().fill(FlameyClosetStyle.ember))
                            .offset(x: 3, y: -2)
                    }
                }
                Text(outfit.name)
                    .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(current ? .black : .white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize()
                if current {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.black)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .frame(height: 40)
            .background(Capsule().fill(current ? Color.white : Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(current ? Color.clear : Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(FlameyTilePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Outfit, \(outfit.name)" + (current ? ", on him now" : "")
                            + (unavailable ? ", some items aren't unlocked" : ""))
        .accessibilityHint(current ? "" : "Tries it on. Save to wear it.")
        .accessibilityAddTraits(current ? [.isSelected, .isButton] : .isButton)
    }

    private var saveChip: some View {
        let full = model.outfitsFull
        let title = full ? "Replace an outfit" : (model.outfits.isEmpty ? "Save this look as an outfit" : "Save as outfit")
        return Button(action: onSaveAs) {
            HStack(spacing: 6) {
                Image(systemName: full ? "arrow.triangle.2.circlepath" : "plus")
                    .madFont(size: 12, weight: .heavy, maxScale: 1.3)
                    .accessibilityHidden(true)
                Text(title)
                    .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(FlameyClosetStyle.ember)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Capsule().fill(FlameyClosetStyle.ember.opacity(0.08)))
            .overlay(Capsule().strokeBorder(FlameyClosetStyle.ember.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(full ? "All \(FlameyOutfit.max) outfits are saved — pick one to replace with this look"
                                : "Keeps this look to put on again in one tap")
    }
}

// MARK: - Save as outfit

/// Names the draft and keeps it. With five saved, the same sheet asks which
/// one this look replaces — the full state is a choice, never a dead end.
struct FlameyOutfitSaveSheet: View {
    let model: FlameyClosetModel
    var still: Bool = false
    var onClose: () -> Void = {}

    @State private var text: String
    @State private var replacing: FlameyOutfit.ID?
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Bool

    init(model: FlameyClosetModel, still: Bool = false, text: String? = nil,
         replacing: FlameyOutfit.ID? = nil, error: String? = nil, onClose: @escaping () -> Void = {}) {
        self.model = model
        self.still = still
        self.onClose = onClose
        _text = State(initialValue: text ?? model.suggestedOutfitName)
        _replacing = State(initialValue: replacing)
        _error = State(initialValue: error)
    }

    private var full: Bool { model.outfitsFull }
    private var duplicate: FlameyOutfit? { model.currentOutfit }

    var body: some View {
        VStack(spacing: 0) {
            FlameySheetScroll(still: still) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        preview
                        VStack(alignment: .leading, spacing: 4) {
                            Text(full ? "REPLACE AN OUTFIT" : "SAVE AS OUTFIT")
                                .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.3)
                                .tracking(1.2)
                                .foregroundColor(FlameyClosetStyle.ember)
                            Text("Keep this look")
                                .madFont(size: 24, weight: .black, design: .rounded)
                                .foregroundColor(.white)
                                .accessibilityAddTraits(.isHeader)
                            Text("Put it back on in one tap from the Closet.")
                                .madFont(size: 13.5, weight: .semibold, design: .rounded)
                                .foregroundColor(.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let duplicate {
                        noteRow(icon: "checkmark.circle.fill", text: "This exact look is already saved as \(duplicate.name).",
                                tint: FlameyClosetStyle.worn)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.white.opacity(0.6))
                        FlameyTextField(placeholder: model.suggestedOutfitName, text: $text,
                                        maxLength: FlameyNameRules.outfitMaxLength, still: still, isError: error != nil,
                                        onSubmit: save)
                            .focused($focused)
                        FlameyFieldNote(error: error, hint: "Up to \(FlameyNameRules.outfitMaxLength) characters. Friends never see outfit names.")
                    }
                    if full { replaceList }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 12)
            }
            VStack(spacing: 4) {
                FlameyWideButton(title: saveTitle, icon: full ? "arrow.triangle.2.circlepath" : "checkmark",
                                 busy: busy, enabled: !full || replacing != nil, action: save)
                FlameyTextButton(title: "Cancel", action: onClose)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(FlameyClosetStyle.ground.ignoresSafeArea())
        .madTypeCap(.madCardCap)
        .onChange(of: text) { _, _ in error = nil }
    }

    private var saveTitle: String {
        guard full else { return "Save outfit" }
        guard let id = replacing, let old = model.outfits.first(where: { $0.id == id }) else { return "Pick one to replace" }
        return "Replace \(old.name)"
    }

    private var preview: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(RadialGradient(colors: [glow.opacity(0.26), Color.white.opacity(0.03)],
                                     center: UnitPoint(x: 0.5, y: 0.62), startRadius: 2, endRadius: 80))
            Ellipse().fill(Color.white.opacity(0.07)).frame(width: 74, height: 10).padding(.bottom, 10)
            FlameyDressedFigure(look: model.stageLook, health: .healthy, size: 68, scale: 1)
                .frame(width: 68, height: 68)
                .padding(.bottom, 13)
        }
        .frame(width: 98, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityLabel(FlameyStage.accessibilityLabel(model.stageLook, name: model.displayName))
    }

    private var glow: Color {
        FlameyPalette.palette(for: model.stageLook.color)?.glow ?? Color(red: 1, green: 0.55, blue: 0.2)
    }

    private var replaceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            noteRow(icon: "tray.full.fill",
                    text: "All \(FlameyOutfit.max) outfit slots are full. Pick one for this look to replace — or delete one from Edit.",
                    tint: FlameyClosetStyle.ember)
            VStack(spacing: 0) {
                ForEach(Array(model.outfits.enumerated()), id: \.element.id) { index, outfit in
                    if index > 0 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 58) }
                    let picked = replacing == outfit.id
                    Button {
                        MADHaptics.tap()
                        replacing = outfit.id
                    } label: {
                        HStack(spacing: 12) {
                            FlameyOutfitThumb(model: model, outfit: outfit, size: 40)
                            Text(outfit.name)
                                .madFont(size: 15, weight: .heavy, design: .rounded)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(picked ? FlameyClosetStyle.ember : .white.opacity(0.3))
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Replace \(outfit.name)")
                    .accessibilityAddTraits(picked ? [.isSelected, .isButton] : .isButton)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func noteRow(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .accessibilityHidden(true)
            Text(text)
                .madFont(size: 13.5, weight: .semibold, design: .rounded)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard !busy else { return }
        if full && replacing == nil {
            error = "Pick the outfit this look replaces."
            return
        }
        busy = true
        Task { @MainActor in
            let outcome = await model.saveOutfit(named: text, replacing: full ? replacing : nil)
            busy = false
            if case .rejected(let message) = outcome {
                error = message
                MADHaptics.error()
            } else {
                MADHaptics.success()
                model.announce(outcome == .deferred ? "Outfit saved on this phone — it syncs later"
                                                    : "Saved as \(FlameyNameRules.normalize(text))")
                onClose()
            }
        }
    }
}

/// A saved outfit's little portrait.
struct FlameyOutfitThumb: View {
    let model: FlameyClosetModel
    let outfit: FlameyOutfit
    var size: CGFloat = 40

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle().fill(Color.white.opacity(0.07))
            FlameyDressedFigure(look: model.look(for: model.wearable(outfit), detail: .compact),
                                health: .healthy, size: size * 0.8, scale: 1)
                .frame(width: size * 0.8, height: size * 0.8)
                .padding(.bottom, size * 0.06)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Edit outfits

/// Rename, reorder and delete. Every change is written at once (it is a
/// list edit, not a look), and a refusal says why on the row it came from.
struct FlameyOutfitsManageSheet: View {
    let model: FlameyClosetModel
    var still: Bool = false
    var onClose: () -> Void = {}

    @State private var editing: FlameyOutfit.ID?
    @State private var text = ""
    @State private var confirmDelete: FlameyOutfit.ID?
    @State private var errors: [FlameyOutfit.ID: String] = [:]
    @FocusState private var focused: Bool

    init(model: FlameyClosetModel, still: Bool = false, editing: FlameyOutfit.ID? = nil, text: String = "",
         confirmDelete: FlameyOutfit.ID? = nil, errors: [FlameyOutfit.ID: String] = [:], onClose: @escaping () -> Void = {}) {
        self.model = model
        self.still = still
        self.onClose = onClose
        _editing = State(initialValue: editing)
        _text = State(initialValue: text)
        _confirmDelete = State(initialValue: confirmDelete)
        _errors = State(initialValue: errors)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your outfits")
                        .madFont(size: 24, weight: .black, design: .rounded)
                        .foregroundColor(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(model.outfits.count) of \(FlameyOutfit.max) saved · tap one in the Closet to try it on")
                        .madFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Text("Done")
                        .madFont(size: 16, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(FlameyClosetStyle.ember)
                        .fixedSize()
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
            FlameySheetScroll(still: still) {
                VStack(spacing: 10) {
                    ForEach(Array(model.outfits.enumerated()), id: \.element.id) { index, outfit in
                        row(outfit, index: index)
                    }
                    if model.outfits.isEmpty {
                        Text("No outfits yet. Dress him up, then “Save as outfit”.")
                            .madFont(size: 14, weight: .semibold, design: .rounded)
                            .foregroundColor(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(FlameyClosetStyle.ground.ignoresSafeArea())
        .madTypeCap(.madCardCap)
    }

    @ViewBuilder
    private func row(_ outfit: FlameyOutfit, index: Int) -> some View {
        let missing = model.unavailableItems(in: outfit)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                FlameyOutfitThumb(model: model, outfit: outfit, size: 46)
                if editing == outfit.id {
                    FlameyTextField(placeholder: outfit.name, text: $text, maxLength: FlameyNameRules.outfitMaxLength,
                                    still: still, isError: errors[outfit.id] != nil, onSubmit: { commitRename(outfit) })
                        .focused($focused)
                    Button { commitRename(outfit) } label: {
                        Text("Save")
                            .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.white)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(Capsule().fill(FlameyClosetStyle.primaryFill))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outfit.name)
                            .madFont(size: 16, weight: .heavy, design: .rounded)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(summary(outfit, missing: missing))
                            .madFont(size: 12, weight: .semibold, design: .rounded)
                            .foregroundColor(model.hasUnavailable(outfit) ? FlameyClosetStyle.ember : .white.opacity(0.5))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    rowControls(outfit, index: index)
                }
            }
            if confirmDelete == outfit.id {
                HStack(spacing: 8) {
                    Text("Delete \(outfit.name)?")
                        .madFont(size: 13.5, weight: .bold, design: .rounded)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button { confirmDelete = nil } label: {
                        Text("Keep")
                            .madFont(size: 13.5, weight: .bold, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.white.opacity(0.75))
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { delete(outfit) } label: {
                        Text("Delete")
                            .madFont(size: 13.5, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.white)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(FlameyClosetStyle.newDot.opacity(0.85)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 58)
            }
            if let error = errors[outfit.id] {
                FlameyFieldNote(error: error, hint: "")
                    .padding(.leading, 58)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func rowControls(_ outfit: FlameyOutfit, index: Int) -> some View {
        HStack(spacing: 2) {
            iconButton("pencil", label: "Rename \(outfit.name)") {
                text = outfit.name
                confirmDelete = nil
                editing = outfit.id
                focused = true
            }
            iconButton("arrow.up", label: "Move \(outfit.name) up", enabled: index > 0) {
                Task { @MainActor in report(outfit.id, await model.moveOutfit(outfit.id, by: -1)) }
            }
            iconButton("arrow.down", label: "Move \(outfit.name) down", enabled: index < model.outfits.count - 1) {
                Task { @MainActor in report(outfit.id, await model.moveOutfit(outfit.id, by: 1)) }
            }
            iconButton("trash", label: "Delete \(outfit.name)", tint: FlameyClosetStyle.newDot) {
                editing = nil
                confirmDelete = outfit.id
            }
        }
    }

    private func iconButton(_ icon: String, label: String, enabled: Bool = true, tint: Color = .white.opacity(0.8),
                            action: @escaping () -> Void) -> some View {
        Button(action: {
            MADHaptics.tap()
            action()
        }) {
            Image(systemName: icon)
                .madFont(size: 13, weight: .bold, maxScale: 1.3)
                .foregroundColor(enabled ? tint : .white.opacity(0.2))
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func summary(_ outfit: FlameyOutfit, missing: [FlameyItem]) -> String {
        if missing.count == 1 { return "No \(missing[0].displayName) yet — worn without it" }
        if missing.count > 1 { return "\(missing.count) items locked — worn without them" }
        if !outfit.ownedOK { return "Some items locked — worn without them" }
        let items = model.wearable(outfit).items.filter { $0.slot.basicItem != $0 }
        if items.isEmpty { return "Basic — nothing on" }
        let names = items.prefix(3).map(\.displayName).joined(separator: ", ")
        return items.count > 3 ? names + " +\(items.count - 3)" : names
    }

    private func commitRename(_ outfit: FlameyOutfit) {
        Task { @MainActor in
            let outcome = await model.renameOutfit(outfit.id, to: text)
            report(outfit.id, outcome)
            if !outcome.isRejected { editing = nil }
        }
    }

    private func delete(_ outfit: FlameyOutfit) {
        MADHaptics.warning()
        confirmDelete = nil
        Task { @MainActor in report(outfit.id, await model.deleteOutfit(outfit.id)) }
    }

    private func report(_ id: FlameyOutfit.ID, _ outcome: FlameySaveOutcome) {
        if case .rejected(let message) = outcome { errors[id] = message } else { errors[id] = nil }
    }
}

// MARK: - His name

/// "Name your Flamey": a field, the rule (or the problem), Save — and a way
/// back to plain "Flamey". Saved on its own, not with the look: a name is
/// typed on purpose, so it needs no draft.
struct FlameyNameEditor: View {
    let model: FlameyClosetModel
    var still: Bool = false
    var onClose: () -> Void = {}

    @State private var text: String
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Bool

    init(model: FlameyClosetModel, still: Bool = false, text: String? = nil, error: String? = nil,
         onClose: @escaping () -> Void = {}) {
        self.model = model
        self.still = still
        self.onClose = onClose
        _text = State(initialValue: text ?? (model.name ?? ""))
        _error = State(initialValue: error)
    }

    /// What he'd be called if this were saved.
    private var previewName: String {
        let normalized = FlameyNameRules.normalize(text)
        return normalized.isEmpty ? FlameyNameRules.fallback : normalized
    }

    var body: some View {
        VStack(spacing: 0) {
            FlameySheetScroll(still: still) {
                VStack(spacing: 16) {
                    stage
                    VStack(spacing: 4) {
                        Text("Name your flame")
                            .madFont(size: 26, weight: .black, design: .rounded)
                            .foregroundColor(.white)
                            .accessibilityAddTraits(.isHeader)
                        Text("It's what the app calls him — and what friends see on his card.")
                            .madFont(size: 14, weight: .semibold, design: .rounded)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        FlameyTextField(placeholder: FlameyNameRules.fallback, text: $text, maxLength: FlameyNameRules.maxLength,
                                        still: still, isError: error != nil, onSubmit: save)
                            .focused($focused)
                        FlameyFieldNote(error: error, hint: "Up to \(FlameyNameRules.maxLength) characters — letters, numbers, emoji and - ' . !")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
            VStack(spacing: 4) {
                FlameyWideButton(title: "Save name", icon: "checkmark", busy: busy, action: save)
                if model.name != nil {
                    FlameyTextButton(title: "Go back to “Flamey”", tint: FlameyClosetStyle.ember) {
                        text = ""
                        save()
                    }
                }
                FlameyTextButton(title: "Cancel", action: onClose)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(FlameyClosetStyle.ground.ignoresSafeArea())
        .madTypeCap(.madCardCap)
        .onChange(of: text) { _, new in
            // Say it as they type when it's already too long or has a
            // character that won't go — never wait for Save to find out.
            if case .failure(let issue) = FlameyNameRules.validate(new), issue != .empty {
                error = issue.message()
            } else {
                error = nil
            }
        }
        .onAppear { if !still { focused = true } }
    }

    private var stage: some View {
        var mood = FlameMood(kind: .ready, streak: 0)
        mood.pokeQuip = "Call me \(previewName)!"
        let look = model.look(for: model.savedChoice)
        return ZStack(alignment: .bottom) {
            Ellipse()
                .fill(RadialGradient(colors: [glow(look).opacity(0.35), .clear], center: .center, startRadius: 1, endRadius: 80))
                .frame(width: 160, height: 22)
            FlameBuddyView(health: .healthy, size: 88, mood: mood, still: still, showsMoodBubble: true, look: look)
                .frame(width: 88, height: 88)
                .padding(.bottom, 10)
        }
        .frame(height: 98 + FlameyStage.bubbleRoom(88), alignment: .bottom)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("He says: Call me \(previewName)!")
    }

    private func glow(_ look: FlameyLook) -> Color {
        FlameyPalette.palette(for: look.color)?.glow ?? Color(red: 1, green: 0.55, blue: 0.2)
    }

    private func save() {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            let outcome = await model.rename(text)
            busy = false
            if case .rejected(let message) = outcome {
                error = message
                MADHaptics.error()
            } else {
                MADHaptics.success()
                model.announce(outcome == .deferred ? "Name saved on this phone — it syncs later"
                                                    : (model.name == nil ? "He's Flamey again" : "Say hi to \(model.displayName)!"))
                onClose()
            }
        }
    }
}

/// The Closet's title: "Sparky's Closet ✎" — the way to his name.
struct FlameyClosetTitle: View {
    let name: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("\(FlameyNameRules.possessive(name)) Closet")
                    .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "pencil")
                    .madFont(size: 12, weight: .bold, maxScale: 1.3)
                    .foregroundColor(FlameyClosetStyle.ember)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(FlameyNameRules.possessive(name)) Closet")
        .accessibilityHint("Rename him")
        .accessibilityAddTraits(.isHeader)
    }
}
