import SwiftUI
import UniformTypeIdentifiers

// FLAMEY'S CLOSET — saving, outfits, his name, and HOW a medal was earned.
// Every piece here is pure (the macOS harness renders them from stub data):
// the model carries the callbacks, `FlameyClosetLive.swift` wires them.
//
// THE SAVE MODEL: the Closet is an editing session. Taps change a DRAFT on
// the stage; the moment it differs from what he wears, `FlameySaveBar`
// docks at the bottom ("Not saved · Undo · Discard · Save"), and leaving
// with a draft raises `FlameyLeavePromptCard` ("Save changes to Sparky's
// look?" Save / Discard / Keep editing). Outfits load INTO the draft too, so
// there is one rule for everything: nothing he wears changes until Save.
//
// NAMES (his, an outfit's) are typed in ONE conventional sheet,
// `FlameyNameEntrySheet`: Cancel · title · Save in a bar at the top, where
// the keyboard can't reach it.

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
            if !text.isEmpty {
                // The standard clear button — a rename usually starts over.
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 28, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
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
/// second bar over the grid — on an SE the two covered it). FIXED height:
/// the Closet pins it to the bottom safe area and it must never resize with
/// what it says (see `FlameyClosetView.bottomDock`).
struct FlameySaveBar: View {
    static let height: CGFloat = 58

    let changes: Int
    let possessiveName: String
    /// The last change ("Trying on Bow Tie"), while it's fresh.
    var note: String? = nil
    /// Steps the draft back one change; nil = nothing to undo.
    var onUndo: (() -> Void)? = nil
    var onDiscard: () -> Void
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Circle().fill(FlameyClosetStyle.ember).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text("Not saved")
                        .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.2)
                        .foregroundColor(.white)
                }
                Text(note ?? (changes == 1 ? "1 change to \(possessiveName) look" : "\(changes) changes to \(possessiveName) look"))
                    .madFont(size: 11.5, weight: .semibold, design: .rounded, maxScale: 1.2)
                    .foregroundColor(.white.opacity(0.55))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            // Always laid out, so the buttons beside it never shift when an
            // undo becomes available or runs out.
            Button { onUndo?() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .madFont(size: 14, weight: .bold, maxScale: 1.2)
                    .foregroundColor(FlameyClosetStyle.ember.opacity(onUndo == nil ? 0.3 : 1))
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onUndo == nil)
            .accessibilityLabel("Undo")
            .accessibilityHint("Takes back the last change")
            Button(action: onDiscard) {
                Text("Discard")
                    .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.2)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Puts back the look he's wearing")
            Button(action: onSave) {
                Text("Save")
                    .madFont(size: 16, weight: .heavy, design: .rounded, maxScale: 1.2)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .background(Capsule().fill(FlameyClosetStyle.primaryFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("He wears this look everywhere")
        }
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(red: 0.13, green: 0.07, blue: 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(FlameyClosetStyle.ember.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }
}

// MARK: - A sheet's navigation bar

/// The standard iOS sheet bar — Cancel on the left, the title, the action
/// on the right — drawn by hand so the harness can photograph it. It sits
/// at the TOP of the sheet, which is the point: a keyboard can never cover
/// an action that lives up here (the old name sheet's Save sat at the
/// bottom and went under the keyboard).
struct FlameySheetNavBar: View {
    let title: String
    var subtitle: String? = nil
    var cancelTitle: String? = "Cancel"
    var onCancel: (() -> Void)? = nil
    var actionTitle: String
    var actionEnabled: Bool = true
    var busy: Bool = false
    var onAction: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(title)
                    .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.2)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.2)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 96)
            HStack {
                if let cancelTitle, let onCancel {
                    Button(action: onCancel) {
                        Text(cancelTitle)
                            .madFont(size: 17, weight: .regular, design: .rounded, maxScale: 1.2)
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button(action: onAction) {
                    Group {
                        if busy {
                            ProgressView().tint(FlameyClosetStyle.ember).controlSize(.small)
                        } else {
                            Text(actionTitle)
                                .madFont(size: 17, weight: .heavy, design: .rounded, maxScale: 1.2)
                                .foregroundColor(actionEnabled ? FlameyClosetStyle.ember : .white.opacity(0.28))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!actionEnabled || busy)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
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

// MARK: - His name plate

/// Under him on the Closet's stage: his name with a pencil — the one,
/// obvious way to name him ("Name your flame" while he's still Flamey).
/// The Closet's title is only a title; renaming the CLOSET was never the
/// idea, and a pencil on the title read that way.
struct FlameyNamePlate: View {
    /// nil = never named (he's "Flamey").
    let name: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let name {
                    Text(name)
                        .madFont(size: 14.5, weight: .heavy, design: .rounded, maxScale: 1.25)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Name your flame")
                        .madFont(size: 13.5, weight: .heavy, design: .rounded, maxScale: 1.25)
                        .foregroundColor(FlameyClosetStyle.ember)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Image(systemName: "pencil")
                    .madFont(size: 11, weight: .bold, maxScale: 1.25)
                    .foregroundColor(FlameyClosetStyle.ember)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(name == nil ? FlameyClosetStyle.ember.opacity(0.10) : Color.white.opacity(0.08)))
            .overlay {
                if name == nil {
                    Capsule().strokeBorder(FlameyClosetStyle.ember.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else {
                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name.map { "Name, \($0)" } ?? "Name your flame")
        .accessibilityHint(name == nil ? "Gives him a name" : "Renames him")
    }
}

// MARK: - A name, typed

/// Every name typed in the Closet — his, a new outfit's, an outfit's
/// rename — is this one conventional sheet: Cancel · title · Save in a bar
/// at the TOP (so the keyboard can never cover the action), one field,
/// pre-filled and focused, with a clear button; Return saves; the rule or
/// the problem under the field, as you type; and an optional reset.
struct FlameyNameEntrySheet<Preview: View>: View {
    let title: String
    let placeholder: String
    let maxLength: Int
    let hint: String
    /// What the field starts with.
    let initial: String
    /// Save needs the text to differ from `initial` (a rename); false for
    /// a new outfit, whose suggested name is savable as-is.
    var requiresChange: Bool = true
    /// Blank is a valid answer (his name: blank = "Flamey").
    var allowsEmpty: Bool = false
    var resetTitle: String? = nil
    var still: Bool = false
    @ViewBuilder var preview: (String) -> Preview
    var onSave: (String) async -> FlameySaveOutcome
    var onReset: (() async -> FlameySaveOutcome)? = nil
    var onClose: () -> Void = {}

    @State private var text: String
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Bool

    init(title: String, placeholder: String, maxLength: Int, hint: String, initial: String,
         requiresChange: Bool = true, allowsEmpty: Bool = false, resetTitle: String? = nil,
         still: Bool = false, text: String? = nil, error: String? = nil,
         @ViewBuilder preview: @escaping (String) -> Preview,
         onSave: @escaping (String) async -> FlameySaveOutcome,
         onReset: (() async -> FlameySaveOutcome)? = nil, onClose: @escaping () -> Void = {}) {
        self.title = title
        self.placeholder = placeholder
        self.maxLength = maxLength
        self.hint = hint
        self.initial = initial
        self.requiresChange = requiresChange
        self.allowsEmpty = allowsEmpty
        self.resetTitle = resetTitle
        self.still = still
        self.preview = preview
        self.onSave = onSave
        self.onReset = onReset
        self.onClose = onClose
        _text = State(initialValue: text ?? initial)
        _error = State(initialValue: error)
    }

    private var normalized: String { FlameyNameRules.normalize(text) }

    private var canSave: Bool {
        guard error == nil else { return false }
        if normalized.isEmpty { return allowsEmpty && FlameyNameRules.normalize(initial) != "" }
        if case .failure = FlameyNameRules.validate(text, maxLength: maxLength) { return false }
        return !requiresChange || normalized != FlameyNameRules.normalize(initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            FlameySheetNavBar(title: title, onCancel: onClose, actionTitle: "Save",
                              actionEnabled: canSave, busy: busy, onAction: save)
            FlameySheetScroll(still: still) {
                VStack(spacing: 16) {
                    preview(normalized)
                    VStack(alignment: .leading, spacing: 8) {
                        FlameyTextField(placeholder: placeholder, text: $text, maxLength: maxLength, still: still,
                                        isError: error != nil, submitLabel: .done, onSubmit: save)
                            .focused($focused)
                        FlameyFieldNote(error: error, hint: hint)
                    }
                    if let resetTitle, let onReset {
                        Button {
                            guard !busy else { return }
                            busy = true
                            Task { @MainActor in
                                let outcome = await onReset()
                                busy = false
                                if case .rejected(let message) = outcome {
                                    error = message
                                    MADHaptics.error()
                                } else {
                                    MADHaptics.success()
                                    onClose()
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .madFont(size: 13, weight: .bold, maxScale: 1.3)
                                    .accessibilityHidden(true)
                                Text(resetTitle)
                                    .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                                    .lineLimit(1)
                            }
                            .foregroundColor(FlameyClosetStyle.ember)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .background(FlameyClosetStyle.ground.ignoresSafeArea())
        .madTypeCap(.madCardCap)
        .onChange(of: text) { _, new in
            // Say it as they type when it's too long or has a character that
            // won't go — never wait for Save to find out.
            if case .failure(let issue) = FlameyNameRules.validate(new, maxLength: maxLength), issue != .empty {
                error = issue.message(maxLength: maxLength)
            } else {
                error = nil
            }
        }
        .onAppear { if !still { focused = true } }
    }

    private func save() {
        guard canSave, !busy else {
            if normalized.isEmpty && !allowsEmpty { error = FlameyNameIssue.empty.message(maxLength: maxLength) }
            return
        }
        busy = true
        Task { @MainActor in
            let outcome = await onSave(text)
            busy = false
            if case .rejected(let message) = outcome {
                error = message
                MADHaptics.error()
            } else {
                MADHaptics.success()
                onClose()
            }
        }
    }
}

/// His name, in the conventional sheet: him saying it, the field, and a
/// way back to plain "Flamey".
struct FlameyNameEditor: View {
    let model: FlameyClosetModel
    var still: Bool = false
    var text: String? = nil
    var error: String? = nil
    var onClose: () -> Void = {}

    var body: some View {
        FlameyNameEntrySheet(
            title: model.name == nil ? "Name your flame" : "Rename \(model.displayName)",
            placeholder: FlameyNameRules.fallback, maxLength: FlameyNameRules.maxLength,
            hint: "Up to \(FlameyNameRules.maxLength) characters — letters, numbers, emoji and - ' . ! Friends see it on his card.",
            initial: model.name ?? "", allowsEmpty: true,
            resetTitle: model.name == nil ? nil : "Reset to “\(FlameyNameRules.fallback)”",
            still: still, text: text, error: error,
            preview: { typed in stage(typed.isEmpty ? FlameyNameRules.fallback : typed) },
            onSave: { raw in
                let outcome = await model.rename(raw)
                if !outcome.isRejected { announce(outcome) }
                return outcome
            },
            onReset: {
                let outcome = await model.rename(nil)
                if !outcome.isRejected { announce(outcome) }
                return outcome
            },
            onClose: onClose)
    }

    private func announce(_ outcome: FlameySaveOutcome) {
        model.announce(outcome == .deferred ? "Name saved on this phone — it syncs later"
                                            : (model.name == nil ? "He's Flamey again" : "Say hi to \(model.displayName)!"))
    }

    private func stage(_ name: String) -> some View {
        var mood = FlameMood(kind: .ready, streak: 0)
        mood.pokeQuip = "Call me \(name)!"
        let look = model.look(for: model.savedChoice)
        let glow = FlameyPalette.palette(for: look.color)?.glow ?? Color(red: 1, green: 0.55, blue: 0.2)
        return ZStack(alignment: .bottom) {
            Ellipse()
                .fill(RadialGradient(colors: [glow.opacity(0.35), .clear], center: .center, startRadius: 1, endRadius: 70))
                .frame(width: 140, height: 20)
            FlameBuddyView(health: .healthy, size: 96, mood: mood, still: still, showsMoodBubble: true, look: look)
                .frame(width: 96, height: 96)
                .padding(.bottom, 8)
        }
        .frame(height: 104 + FlameyStage.bubbleRoom(96), alignment: .bottom)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("He says: Call me \(name)!")
    }
}

// MARK: - Outfits: a portrait

/// A saved outfit's little portrait (chips, lists).
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

extension FlameyClosetModel.OutfitStatus {
    /// "Wearing Sunday Best" / "Trying on Race day" / "New look — not saved as an outfit".
    var line: String? {
        switch self {
        case .wearing(let name): return "Wearing \(name)"
        case .tryingOn(let name): return "Trying on \(name)"
        case .newLook: return "New look — not an outfit yet"
        case .noOutfit: return nil
        }
    }

    var tint: Color {
        switch self {
        case .wearing: return FlameyClosetStyle.worn
        case .tryingOn: return FlameyClosetStyle.ember
        case .newLook, .noOutfit: return .white.opacity(0.55)
        }
    }
}

// MARK: - Outfits: the Closet's shortcut row

/// Under the stage: "OUTFITS · Wearing Sunday Best · See all ›", then one
/// chip per outfit (a tiny him + the name) — tap loads it into the draft,
/// Save wears it. The one he WEARS carries a green check; the one on the
/// stage but unsaved is filled white. The trailing chip saves the look on
/// the stage when it isn't an outfit yet ("Outfits full" opens the page).
struct FlameyOutfitsShortcut: View {
    let model: FlameyClosetModel
    var scrollable: Bool = true
    var onOpen: () -> Void
    var onSaveLook: () -> Void

    static let height: CGFloat = 70

    /// No outfits and nothing on the stage worth saving: the one line says
    /// what outfits are, and the chip row isn't drawn (it would be an empty
    /// 44pt band on the header an SE can least afford).
    private var headerOnly: Bool { model.outfits.isEmpty && !model.canSaveDraftAsOutfit }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !headerOnly { chips }
        }
        .frame(height: headerOnly ? 18 : Self.height, alignment: .top)
    }

    private var header: some View {
        let status = model.outfitStatus
        return Button(action: onOpen) {
            HStack(spacing: 6) {
                Text("OUTFITS")
                    .madFont(size: 11, weight: .black, design: .rounded, maxScale: 1.2)
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize()
                if headerOnly {
                    Text("·").foregroundColor(.white.opacity(0.3)).font(.system(size: 11, weight: .black))
                    Text("Save a look, wear it again in one tap")
                        .madFont(size: 11.5, weight: .semibold, design: .rounded, maxScale: 1.2)
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if let line = status.line {
                    Text("·").foregroundColor(.white.opacity(0.3)).font(.system(size: 11, weight: .black))
                    Text(line)
                        .madFont(size: 11.5, weight: .heavy, design: .rounded, maxScale: 1.2)
                        .foregroundColor(status.tint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(model.outfits.isEmpty ? "Open" :"See all \(model.outfits.count)")
                    .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.2)
                    .foregroundColor(FlameyClosetStyle.ember)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(FlameyClosetStyle.ember)
                    .accessibilityHidden(true)
            }
            .frame(height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Outfits" + (status.line.map { ", \($0)" } ?? "") + ", \(model.outfits.count) of \(FlameyOutfit.max) saved")
        .accessibilityHint("Opens your outfits")
    }

    @ViewBuilder
    private var chips: some View {
        let row = HStack(spacing: 6) {
            ForEach(model.outfits) { outfit in
                chip(outfit)
            }
            trailingChip
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
        .frame(height: 44)
    }

    private func chip(_ outfit: FlameyOutfit) -> some View {
        let worn = !model.hasUnsavedChanges && model.currentOutfit?.id == outfit.id
        let previewing = model.isPreviewing(outfit)
        let unavailable = model.hasUnavailable(outfit)
        return Button {
            MADHaptics.tap()
            withAnimation(.snappy) { model.tryOn(outfit) }
        } label: {
            HStack(spacing: 6) {
                FlameyOutfitThumb(model: model, outfit: outfit, size: 34)
                    .overlay(alignment: .bottomTrailing) {
                        if worn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7.5, weight: .black))
                                .foregroundColor(.black)
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(FlameyClosetStyle.worn))
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
                                .offset(x: 3, y: 2)
                        } else if unavailable {
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 7, weight: .black))
                                .foregroundColor(.black)
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(FlameyClosetStyle.ember))
                                .offset(x: 3, y: 2)
                        }
                    }
                Text(outfit.name)
                    .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.2)
                    .foregroundColor(previewing ? .black : .white.opacity(0.92))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.leading, 4)
            .padding(.trailing, 13)
            .frame(height: 42)
            .background(Capsule().fill(previewing ? Color.white : Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(worn ? FlameyClosetStyle.worn.opacity(0.8)
                                                 : (previewing ? Color.clear : Color.white.opacity(0.12)),
                                            lineWidth: worn ? 1.5 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(FlameyTilePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Outfit, \(outfit.name)" + (worn ? ", wearing" : "") + (previewing ? ", trying on" : "")
                            + (unavailable ? ", some items aren't unlocked" : ""))
        .accessibilityHint(worn ? "" : "Tries it on. Save to wear it.")
        .accessibilityAddTraits(worn || previewing ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var trailingChip: some View {
        if model.canSaveDraftAsOutfit {
            let full = model.outfitsFull
            Button(action: full ? onOpen : onSaveLook) {
                HStack(spacing: 6) {
                    Image(systemName: full ? "tray.full" : "plus")
                        .madFont(size: 12, weight: .heavy, maxScale: 1.2)
                        .accessibilityHidden(true)
                    Text(full ? "Outfits full" : "Save as outfit")
                        .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.2)
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundColor(FlameyClosetStyle.ember)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Capsule().fill(FlameyClosetStyle.ember.opacity(0.08)))
                .overlay(Capsule().strokeBorder(FlameyClosetStyle.ember.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(full ? "All \(FlameyOutfit.max) are saved — opens your outfits to update or delete one"
                                    : "Keeps this look to put back on in one tap")
        }
    }
}

// MARK: - Outfits: the page

/// What the ••• on an outfit card offers — one list, so the menu and the
/// harness's picture of it can't disagree.
enum FlameyOutfitMenuAction: CaseIterable, Identifiable {
    case rename, update, moveEarlier, moveLater, delete
    var id: Self { self }

    var title: String {
        switch self {
        case .rename: return "Rename"
        case .update: return "Update with current look"
        case .moveEarlier: return "Move earlier"
        case .moveLater: return "Move later"
        case .delete: return "Delete"
        }
    }

    var icon: String {
        switch self {
        case .rename: return "pencil"
        case .update: return "arrow.triangle.2.circlepath"
        case .moveEarlier: return "arrow.left"
        case .moveLater: return "arrow.right"
        case .delete: return "trash"
        }
    }

    var isDestructive: Bool { self == .delete }
}

/// Outfits as a first-class thing: a page of big cards — him wearing each
/// one, its name, WEARING on the one he has on and TRYING ON on the one on
/// the stage. Tap a card to try it on (the page closes onto the stage, where
/// Save wears it); ••• renames it, updates it with the look on the stage,
/// moves or deletes it; drag to reorder. The last card saves the look on
/// the stage as a new outfit (and says why not, when it can't).
struct FlameyOutfitsSheet: View {
    let model: FlameyClosetModel
    var still: Bool = false
    /// The harness draws one card's menu open.
    var stillMenuFor: FlameyOutfit.ID? = nil
    var onClose: () -> Void = {}

    enum Entry: Identifiable {
        case new
        case rename(FlameyOutfit.ID)
        var id: String {
            switch self {
            case .new: return "new"
            case .rename(let id): return "rename-\(id)"
            }
        }
    }

    enum Confirm: Identifiable {
        case delete(FlameyOutfit)
        case update(FlameyOutfit)
        var id: String {
            switch self {
            case .delete(let o): return "delete-\(o.id)"
            case .update(let o): return "update-\(o.id)"
            }
        }
    }

    @State private var entry: Entry?
    @State private var confirm: Confirm?
    @State private var dragOrder: [FlameyOutfit.ID]?
    @State private var dragging: FlameyOutfit.ID?
    @State private var error: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var shown: [FlameyOutfit] {
        guard let dragOrder else { return model.outfits }
        return dragOrder.compactMap { id in model.outfits.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            FlameySheetNavBar(title: "Outfits", subtitle: "\(model.outfits.count) of \(FlameyOutfit.max) saved",
                              cancelTitle: nil, onCancel: nil, actionTitle: "Done", onAction: onClose)
            FlameySheetScroll(still: still) {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    if model.outfits.isEmpty { emptyExplainer }
                    if let error {
                        FlameyFieldNote(error: error, hint: "")
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(shown) { outfit in
                            card(outfit)
                        }
                        if !model.outfits.isEmpty { saveCard }
                    }
                    // A drop between cards still lands the new order (and
                    // never leaves a card stuck half-faded).
                    .modifier(GridDrop(enabled: !still) {
                        if let order = dragOrder { run { await model.reorderOutfits(order) } }
                        dragOrder = nil
                        dragging = nil
                    })
                    if model.outfits.isEmpty { saveCard }
                    if model.outfits.count > 1 {
                        Text("Touch and hold a card to drag it into a new order.")
                            .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.white.opacity(0.4))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .background(FlameyClosetStyle.ground.ignoresSafeArea())
        .madTypeCap(.madCardCap)
        .sheet(item: $entry) { which in
            entrySheet(which)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(FlameyClosetStyle.ground)
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { which in
            switch which {
            case .delete(let outfit):
                Button("Delete \(outfit.name)", role: .destructive) {
                    MADHaptics.warning()
                    run { await model.deleteOutfit(outfit.id) }
                }
            case .update(let outfit):
                Button("Update \(outfit.name)") {
                    MADHaptics.success()
                    run { await model.updateOutfit(outfit.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { which in
            switch which {
            case .delete: Text("It's only the outfit — nothing he owns goes anywhere.")
            case .update(let outfit): Text("\(outfit.name) will be the look on the stage right now. Its name stays.")
            }
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .delete(let o): return "Delete \(o.name)?"
        case .update(let o): return "Update \(o.name)?"
        case nil: return ""
        }
    }

    // The stage, in one line — what's on him relative to these outfits.

    private var statusCard: some View {
        let status = model.outfitStatus
        let (title, detail): (String, String) = {
            switch status {
            case .wearing(let name): return ("Wearing \(name)", "Saved — it's his look everywhere.")
            case .tryingOn(let name): return ("Trying on \(name)", "Tap Done, then Save to wear it.")
            case .newLook: return ("A new look on the stage", model.outfitsFull
                                   ? "It isn't an outfit yet — update one below to keep it."
                                   : "It isn't an outfit yet. Save it to put it back on in one tap.")
            case .noOutfit: return (model.choice.isBasic ? "Basic \(model.displayName)" : "No outfit on",
                                model.outfits.isEmpty ? "Dress him up in the Closet, then save the look here."
                                                      : "Tap an outfit to try it on.")
            }
        }()
        return HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                Circle().fill(glow(model.stageLook).opacity(0.2))
                FlameyDressedFigure(look: model.look(for: model.choice, detail: .compact), health: .healthy, size: 46, scale: 1)
                    .frame(width: 46, height: 46)
                    .padding(.bottom, 3)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("ON THE STAGE")
                    .madFont(size: 10, weight: .black, design: .rounded, maxScale: 1.2)
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.4))
                Text(title)
                    .madFont(size: 16, weight: .heavy, design: .rounded)
                    .foregroundColor(status == .noOutfit ? .white : status.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .madFont(size: 12.5, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var emptyExplainer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Save looks you love")
                .madFont(size: 22, weight: .black, design: .rounded)
                .foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)
            Text("An outfit keeps a whole look — color, hat, cape, the lot — so you can put it back on in one tap. Keep up to \(FlameyOutfit.max).")
                .madFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // A card

    private func card(_ outfit: FlameyOutfit) -> some View {
        let worn = model.wornOutfit?.id == outfit.id
        let previewing = model.isPreviewing(outfit)
        let missing = model.unavailableItems(in: outfit)
        let look = model.look(for: model.wearable(outfit))
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return ZStack(alignment: .top) {
            Button {
                MADHaptics.tap()
                withAnimation(.snappy) { model.tryOn(outfit) }
                onClose()
            } label: {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        RadialGradient(colors: [glow(look).opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.7),
                                       startRadius: 2, endRadius: 90)
                        Ellipse().fill(Color.white.opacity(0.07)).frame(width: 96, height: 12).padding(.bottom, 8)
                        FlameyDressedFigure(look: look, health: .healthy, size: 92, scale: 1)
                            .frame(width: 92, height: 92)
                            .padding(.bottom, 12)
                    }
                    .frame(height: 138)
                    .clipped()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outfit.name)
                            .madFont(size: 15, weight: .heavy, design: .rounded, maxScale: 1.3)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(summary(outfit, missing: missing))
                            .madFont(size: 11.5, weight: .semibold, design: .rounded, maxScale: 1.3)
                            .foregroundColor(missing.isEmpty && outfit.ownedOK ? .white.opacity(0.5) : FlameyClosetStyle.ember)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .background(shape.fill(Color.white.opacity(0.05)))
                .overlay(shape.strokeBorder(worn ? FlameyClosetStyle.worn.opacity(0.85)
                                                 : (previewing ? FlameyClosetStyle.ember.opacity(0.85) : Color.white.opacity(0.08)),
                                            lineWidth: worn || previewing ? 1.5 : 1))
                .clipShape(shape)
                .contentShape(shape)
            }
            .buttonStyle(FlameyTilePressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(outfit.name)" + (worn ? ", wearing" : "") + (previewing ? ", trying on" : "")
                                + ". " + summary(outfit, missing: missing))
            .accessibilityHint(worn ? "He's wearing this" : "Tries it on. Save to wear it.")
            .accessibilityAddTraits(worn || previewing ? [.isSelected, .isButton] : .isButton)
            // Siblings of the card's button, never inside it (a button in a
            // button's label doesn't reliably get its taps).
            HStack(alignment: .top) {
                if worn {
                    badge("WEARING", icon: "checkmark", tint: FlameyClosetStyle.worn)
                } else if previewing {
                    badge("TRYING ON", icon: "eye", tint: FlameyClosetStyle.ember)
                }
                Spacer(minLength: 0)
                menu(outfit)
            }
            .padding(8)
        }
        .opacity(dragging == outfit.id ? 0.4 : 1)
        .modifier(Reorderable(enabled: !still, id: outfit.id, dragOrder: $dragOrder, dragging: $dragging,
                              all: model.outfits.map(\.id)) { ids in
            run { await model.reorderOutfits(ids) }
        })
    }

    private struct GridDrop: ViewModifier {
        let enabled: Bool
        let land: () -> Void

        func body(content: Content) -> some View {
            if enabled {
                content.onDrop(of: [.text], isTargeted: nil) { _ in
                    land()
                    return true
                }
            } else {
                content
            }
        }
    }

    /// Drag to reorder (never in a still — ImageRenderer draws a drag
    /// source as a "can't render" placeholder).
    private struct Reorderable: ViewModifier {
        let enabled: Bool
        let id: FlameyOutfit.ID
        @Binding var dragOrder: [FlameyOutfit.ID]?
        @Binding var dragging: FlameyOutfit.ID?
        let all: [FlameyOutfit.ID]
        let commit: ([FlameyOutfit.ID]) -> Void

        func body(content: Content) -> some View {
            if enabled {
                content
                    .onDrag {
                        dragging = id
                        if dragOrder == nil { dragOrder = all }
                        return NSItemProvider(object: id as NSString)
                    }
                    .onDrop(of: [.text], delegate: FlameyOutfitDropDelegate(target: id, order: $dragOrder,
                                                                           dragging: $dragging, commit: commit))
            } else {
                content
            }
        }
    }

    private func badge(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .black))
                .accessibilityHidden(true)
            Text(text)
                .madFont(size: 9.5, weight: .black, design: .rounded, maxScale: 1.2)
                .tracking(0.6)
        }
        .foregroundColor(.black)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(tint))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func menu(_ outfit: FlameyOutfit) -> some View {
        let index = model.outfits.firstIndex { $0.id == outfit.id } ?? 0
        let dots = Image(systemName: "ellipsis")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white.opacity(0.9))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.black.opacity(0.35)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .frame(width: 44, height: 44, alignment: .topTrailing)
            .contentShape(Rectangle())
        if still {
            dots.overlay(alignment: .topTrailing) {
                if stillMenuFor == outfit.id {
                    FlameyOutfitMenuPicture(outfit: outfit, enabled: { enabled($0, outfit: outfit, index: index) })
                        .offset(x: 6, y: 40)
                }
            }
        } else {
            Menu {
                ForEach(FlameyOutfitMenuAction.allCases) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        perform(action, on: outfit, index: index)
                    } label: {
                        Label(action.title, systemImage: action.icon)
                    }
                    .disabled(!enabled(action, outfit: outfit, index: index))
                }
            } label: { dots }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("More for \(outfit.name)")
        }
    }

    private func enabled(_ action: FlameyOutfitMenuAction, outfit: FlameyOutfit, index: Int) -> Bool {
        switch action {
        case .rename, .delete: return true
        case .update: return model.wearable(outfit) != model.choice || !outfit.ownedOK
        case .moveEarlier: return index > 0
        case .moveLater: return index < model.outfits.count - 1
        }
    }

    private func perform(_ action: FlameyOutfitMenuAction, on outfit: FlameyOutfit, index: Int) {
        MADHaptics.tap()
        switch action {
        case .rename: entry = .rename(outfit.id)
        case .update: confirm = .update(outfit)
        case .delete: confirm = .delete(outfit)
        case .moveEarlier: run { await model.moveOutfit(outfit.id, by: -1) }
        case .moveLater: run { await model.moveOutfit(outfit.id, by: 1) }
        }
    }

    // The save card

    private var saveCard: some View {
        let full = model.outfitsFull
        let duplicate = model.currentOutfit
        let basic = model.choice.isBasic
        let enabled = !full && duplicate == nil && !basic
        let detail: String = {
            if let duplicate { return "Already saved as \(duplicate.name)" }
            if basic { return "Dress him up first — basic needs no outfit" }
            if full { return "All \(FlameyOutfit.max) are saved. Update or delete one to keep a new look." }
            return "Keeps the look on the stage"
        }()
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button {
            MADHaptics.tap()
            entry = .new
        } label: {
            VStack(spacing: 10) {
                Image(systemName: full ? "tray.full" : "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(enabled ? FlameyClosetStyle.ember : .white.opacity(0.35))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(enabled ? FlameyClosetStyle.ember.opacity(0.12) : Color.white.opacity(0.05)))
                    .accessibilityHidden(true)
                VStack(spacing: 3) {
                    Text("Save current look")
                        .madFont(size: 14.5, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(enabled ? .white : .white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .madFont(size: 11.5, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(enabled ? 0.55 : 0.4))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 196)
            .background(shape.fill(enabled ? FlameyClosetStyle.ember.opacity(0.05) : Color.white.opacity(0.025)))
            .overlay(shape.strokeBorder(enabled ? FlameyClosetStyle.ember.opacity(0.5) : Color.white.opacity(0.12),
                                        style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Save current look as an outfit")
        .accessibilityHint(detail)
    }

    // Names

    @ViewBuilder
    private func entrySheet(_ which: Entry) -> some View {
        switch which {
        case .new:
            FlameyOutfitNameSheet(model: model, still: still, onClose: { entry = nil })
        case .rename(let id):
            if let outfit = model.outfits.first(where: { $0.id == id }) {
                FlameyNameEntrySheet(
                    title: "Rename outfit", placeholder: outfit.name, maxLength: FlameyNameRules.outfitMaxLength,
                    hint: "Up to \(FlameyNameRules.outfitMaxLength) characters. Friends never see outfit names.",
                    initial: outfit.name, still: still,
                    preview: { _ in FlameyOutfitNamePreview(look: model.look(for: model.wearable(outfit))) },
                    onSave: { raw in await model.renameOutfit(id, to: raw) },
                    onClose: { entry = nil })
            }
        }
    }

    private func run(_ work: @escaping () async -> FlameySaveOutcome) {
        Task { @MainActor in
            let outcome = await work()
            if case .rejected(let message) = outcome {
                error = message
                MADHaptics.error()
            } else {
                error = nil
            }
        }
    }

    private func summary(_ outfit: FlameyOutfit, missing: [FlameyItem]) -> String {
        if missing.count == 1 { return "No \(missing[0].displayName) yet" }
        if missing.count > 1 { return "\(missing.count) items locked" }
        if !outfit.ownedOK { return "Some items locked" }
        let items = model.wearable(outfit).items.filter { $0.slot.basicItem != $0 }
        if items.isEmpty { return "Basic — nothing on" }
        let names = items.prefix(2).map(\.displayName).joined(separator: " · ")
        return items.count > 2 ? names + " +\(items.count - 2)" : names
    }

    private func glow(_ look: FlameyLook) -> Color {
        FlameyPalette.palette(for: look.color)?.glow ?? Color(red: 1, green: 0.55, blue: 0.2)
    }
}

/// Live reordering while a card is dragged: the order changes as the card
/// passes over another, and the new order is written once, on the drop.
struct FlameyOutfitDropDelegate: DropDelegate {
    let target: FlameyOutfit.ID
    @Binding var order: [FlameyOutfit.ID]?
    @Binding var dragging: FlameyOutfit.ID?
    var commit: ([FlameyOutfit.ID]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, var list = order,
              let from = list.firstIndex(of: dragging), let to = list.firstIndex(of: target) else { return }
        list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.snappy(duration: 0.2)) { order = list }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        if let order { commit(order) }
        dragging = nil
        order = nil
        return true
    }
}

/// The ••• menu, drawn for a still (ImageRenderer can't open a `Menu`) —
/// same actions, same order, same enabled rule as the live one.
struct FlameyOutfitMenuPicture: View {
    let outfit: FlameyOutfit
    var enabled: (FlameyOutfitMenuAction) -> Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(FlameyOutfitMenuAction.allCases.enumerated()), id: \.element) { i, action in
                if i > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                HStack {
                    Text(action.title)
                        .font(.system(size: 15, weight: .regular))
                    Spacer(minLength: 12)
                    Image(systemName: action.icon).font(.system(size: 14))
                }
                .foregroundColor(action.isDestructive ? Color(red: 1, green: 0.35, blue: 0.35)
                                                      : .white.opacity(enabled(action) ? 0.95 : 0.3))
                .padding(.horizontal, 14)
                .frame(height: 42)
            }
        }
        .frame(width: 244)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color(red: 0.19, green: 0.17, blue: 0.18)))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .fixedSize()
    }
}

/// The look an outfit name is for, above its field.
struct FlameyOutfitNamePreview: View {
    let look: FlameyLook

    var body: some View {
        let glow = FlameyPalette.palette(for: look.color)?.glow ?? Color(red: 1, green: 0.55, blue: 0.2)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(RadialGradient(colors: [glow.opacity(0.26), Color.white.opacity(0.03)],
                                     center: UnitPoint(x: 0.5, y: 0.65), startRadius: 2, endRadius: 110))
            Ellipse().fill(Color.white.opacity(0.07)).frame(width: 96, height: 12).padding(.bottom, 12)
            FlameyDressedFigure(look: look, health: .healthy, size: 96, scale: 1)
                .frame(width: 96, height: 96)
                .padding(.bottom, 16)
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// "Save as outfit": names the look on the stage (suggested "Outfit 3").
struct FlameyOutfitNameSheet: View {
    let model: FlameyClosetModel
    var still: Bool = false
    var text: String? = nil
    var error: String? = nil
    var onClose: () -> Void = {}

    var body: some View {
        FlameyNameEntrySheet(
            title: "New outfit", placeholder: model.suggestedOutfitName, maxLength: FlameyNameRules.outfitMaxLength,
            hint: "Up to \(FlameyNameRules.outfitMaxLength) characters. Friends never see outfit names.",
            initial: model.suggestedOutfitName, requiresChange: false, still: still, text: text, error: error,
            preview: { _ in FlameyOutfitNamePreview(look: model.stageLook) },
            onSave: { raw in
                let outcome = await model.saveOutfit(named: raw)
                if !outcome.isRejected {
                    model.announce(outcome == .deferred ? "Outfit saved on this phone — it syncs later"
                                                        : "Saved as \(FlameyNameRules.normalize(raw))")
                }
                return outcome
            },
            onClose: onClose)
    }
}
