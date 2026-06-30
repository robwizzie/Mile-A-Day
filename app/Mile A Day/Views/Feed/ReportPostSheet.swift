import SwiftUI

/// Report-a-post sheet (App Store Guideline 1.2). Reasons mirror the backend
/// `post_reports.reason` check constraint.
struct ReportPostSheet: View {
    let postId: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: String = "spam"
    @State private var details: String = ""
    @State private var submitting = false
    @State private var submitted = false
    @State private var errorMessage: String?

    private let reasons: [(key: String, label: String, icon: String)] = [
        ("spam", "Spam or misleading", "exclamationmark.bubble"),
        ("nudity", "Nudity or sexual content", "eye.slash"),
        ("harassment", "Harassment or bullying", "person.fill.xmark"),
        ("violence", "Violence or threats", "exclamationmark.triangle"),
        ("other", "Something else", "ellipsis.circle")
    ]

    var body: some View {
        NavigationStack {
            Form {
                if submitted {
                    Section {
                        Label("Thanks — our team will review this within 24 hours.", systemImage: "checkmark.seal.fill")
                            .foregroundColor(MADTheme.Colors.success)
                    }
                } else {
                    Section("Why are you reporting this?") {
                        ForEach(reasons, id: \.key) { item in
                            Button { reason = item.key } label: {
                                HStack {
                                    Label(item.label, systemImage: item.icon)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if reason == item.key {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(MADTheme.Colors.madRed)
                                    }
                                }
                            }
                        }
                    }
                    Section("Add details (optional)") {
                        TextField("What's going on?", text: $details, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundColor(MADTheme.Colors.error) }
                    }
                }
            }
            .navigationTitle("Report Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDone(); dismiss() }
                }
                if !submitted {
                    ToolbarItem(placement: .confirmationAction) {
                        if submitting {
                            ProgressView()
                        } else {
                            Button("Submit") { Task { await submit() } }
                                .fontWeight(.bold)
                        }
                    }
                }
            }
        }
    }

    private func submit() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            try await PostService.reportPost(
                postId: postId,
                reason: reason,
                details: details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : details
            )
            submitted = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            onDone()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't submit report."
        }
    }
}
