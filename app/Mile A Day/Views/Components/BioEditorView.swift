import SwiftUI

struct BioEditorView: View {
    let bio: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    @State private var currentBio: String
    @FocusState private var isTextFieldFocused: Bool
    
    init(bio: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.bio = bio
        self.onSave = onSave
        self.onCancel = onCancel
        self._currentBio = State(initialValue: bio)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: MADTheme.Spacing.xl) {
                // Header
                VStack(spacing: MADTheme.Spacing.md) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 50))
                        .foregroundColor(MADTheme.Colors.madRed)
                    
                    Text("Edit Bio")
                        .font(MADTheme.Typography.title1)
                        .fontWeight(.bold)
                        .foregroundColor(MADTheme.Colors.primaryText)
                    
                    Text("Tell others about yourself")
                        .font(MADTheme.Typography.body)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                
                // Bio Input
                VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                    Text("Bio")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(MADTheme.Colors.primaryText)
                    
                    TextField("Tell us about yourself...", text: $currentBio, axis: .vertical)
                        .font(MADTheme.Typography.body)
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .lineLimit(3...8)
                        .padding(MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(MADTheme.Colors.cardBackground)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    Text("\(currentBio.count)/150 characters")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(currentBio.count > 150 ? MADTheme.Colors.error : MADTheme.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: MADTheme.Spacing.md) {
                    Button(action: {
                        onSave(currentBio)
                    }) {
                        Text("Save")
                            .font(MADTheme.Typography.headline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MADTheme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .fill(MADTheme.Colors.madRed)
                            )
                            .foregroundColor(.white)
                    }
                    .disabled(currentBio.count > 150)
                    
                    Button("Cancel", action: onCancel)
                        .font(MADTheme.Typography.body)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
            }
            .padding(MADTheme.Spacing.lg)
            .background(MADTheme.Colors.secondaryBackground)
            .navigationBarHidden(true)
        }
        .onAppear {
            // Focus the text field when the view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }
}

#Preview {
    BioEditorView(
        bio: "I love running and staying active!",
        onSave: { _ in },
        onCancel: { }
    )
}
