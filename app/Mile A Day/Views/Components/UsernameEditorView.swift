import SwiftUI

struct UsernameEditorView: View {
    let currentUsername: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    @State private var username: String
    @State private var isValidating = false
    @State private var validationMessage = ""
    @State private var isValid = false
    @State private var validationTimer: Timer?
    @FocusState private var isTextFieldFocused: Bool
    
    init(currentUsername: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.currentUsername = currentUsername
        self.onSave = onSave
        self.onCancel = onCancel
        self._username = State(initialValue: currentUsername)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: MADTheme.Spacing.xl) {
                // Header
                VStack(spacing: MADTheme.Spacing.md) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(MADTheme.Colors.madRed)
                    
                    Text("Edit Username")
                        .font(MADTheme.Typography.title1)
                        .fontWeight(.bold)
                        .foregroundColor(MADTheme.Colors.primaryText)
                    
                    Text("This will be how friends can find you")
                        .font(MADTheme.Typography.body)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                
                // Username Input
                VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                    Text("Username")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(MADTheme.Colors.primaryText)
                    
                    HStack {
                        Text("@")
                            .font(MADTheme.Typography.body)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                            .padding(.leading, MADTheme.Spacing.md)
                        
                        TextField("Enter username", text: $username)
                            .font(MADTheme.Typography.body)
                            .textFieldStyle(.plain)
                            .focused($isTextFieldFocused)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: username) { oldValue, newValue in
                                validateUsername(newValue)
                            }
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(MADTheme.Colors.cardBackground)
                            .stroke(validationBorderColor, lineWidth: 2)
                    )
                    
                    // Validation Message
                    if !validationMessage.isEmpty {
                        HStack {
                            Image(systemName: validationIcon)
                                .foregroundColor(validationColor)
                            Text(validationMessage)
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(validationColor)
                        }
                    }
                }
                
                // Username Requirements
                VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                    Text("Username Requirements:")
                        .font(MADTheme.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                        RequirementRow(
                            text: "3-20 characters long",
                            isMet: username.count >= 3 && username.count <= 20
                        )
                        RequirementRow(
                            text: "Only letters, numbers, and underscores",
                            isMet: username.isEmpty || username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
                        )
                        RequirementRow(
                            text: "Must start with a letter",
                            isMet: username.isEmpty || username.first?.isLetter == true
                        )
                        RequirementRow(
                            text: "Must be available",
                            isMet: isValid && !isValidating
                        )
                    }
                }
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                        .fill(MADTheme.Colors.secondaryBackground)
                )
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: MADTheme.Spacing.md) {
                    Button(action: {
                        onSave(username)
                    }) {
                        HStack {
                            if isValidating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Save")
                                    .font(MADTheme.Typography.headline)
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(isValid && !isValidating ? MADTheme.Colors.madRed : Color.gray)
                        )
                        .foregroundColor(.white)
                    }
                    .disabled(!isValid || isValidating)
                    
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
    
    // MARK: - Validation Logic
    
    private var validationBorderColor: Color {
        if isValidating {
            return MADTheme.Colors.warning
        } else if isValid && !username.isEmpty {
            return MADTheme.Colors.success
        } else if !validationMessage.isEmpty && !isValid {
            return MADTheme.Colors.error
        } else {
            return Color.gray.opacity(0.3)
        }
    }
    
    private var validationColor: Color {
        if isValidating {
            return MADTheme.Colors.warning
        } else if isValid && !username.isEmpty {
            return MADTheme.Colors.success
        } else {
            return MADTheme.Colors.error
        }
    }
    
    private var validationIcon: String {
        if isValidating {
            return "clock"
        } else if isValid && !username.isEmpty {
            return "checkmark.circle.fill"
        } else {
            return "exclamationmark.circle.fill"
        }
    }
    
    private func validateUsername(_ username: String) {
        // Cancel previous timer
        validationTimer?.invalidate()
        
        // Clear validation if empty
        if username.isEmpty {
            validationMessage = ""
            isValid = false
            return
        }
        
        // Basic validation
        let basicValidation = validateBasicRequirements(username)
        if !basicValidation.isValid {
            validationMessage = basicValidation.message
            isValid = false
            return
        }
        
        // Start debounced server validation
        validationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            Task {
                await checkUsernameAvailability(username)
            }
        }
    }
    
    private func validateBasicRequirements(_ username: String) -> (isValid: Bool, message: String) {
        // Length check
        if username.count < 3 {
            return (false, "Username must be at least 3 characters long")
        }
        
        if username.count > 20 {
            return (false, "Username must be no more than 20 characters long")
        }
        
        // Character check
        if !username.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
            return (false, "Username can only contain letters, numbers, and underscores")
        }
        
        // First character check
        if let firstChar = username.first, !firstChar.isLetter {
            return (false, "Username must start with a letter")
        }
        
        return (true, "")
    }
    
    @MainActor
    private func checkUsernameAvailability(_ username: String) async {
        // Skip validation if it's the same as current username
        if username == currentUsername {
            isValid = true
            validationMessage = "Current username"
            return
        }
        
        isValidating = true
        validationMessage = "Checking availability..."
        
        do {
            let isAvailable = try await UsernameService.checkAvailability(username)
            isValid = isAvailable
            validationMessage = isAvailable ? "Username is available!" : "Username is already taken"
        } catch {
            // If network check fails, just validate basic requirements
            let basicValidation = validateBasicRequirements(username)
            if basicValidation.isValid {
                isValid = true
                validationMessage = "Username looks good (offline)"
            } else {
                isValid = false
                validationMessage = basicValidation.message
            }
        }
        
        isValidating = false
    }
}

#Preview {
    UsernameEditorView(
        currentUsername: "johndoe",
        onSave: { _ in },
        onCancel: { }
    )
}
