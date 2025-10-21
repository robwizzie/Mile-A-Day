import SwiftUI

struct UsernameInputView: View {
    @Binding var username: String
    @State private var isValidating = false
    @State private var validationMessage = ""
    @State private var isValid = false
    @State private var validationTimer: Timer?
    
    let onSubmit: () -> Void
    let onCancel: (() -> Void)?
    
    init(username: Binding<String>, onSubmit: @escaping () -> Void, onCancel: (() -> Void)? = nil) {
        self._username = username
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: MADTheme.Spacing.xl) {
            // Header
            VStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(MADTheme.Colors.madRed)
                
                Text("Choose Your Username")
                    .font(MADTheme.Typography.title1)
                    .fontWeight(.bold)
                    .foregroundColor(MADTheme.Colors.primaryText)
                
                Text("This will be how friends can find and add you")
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            
            // Username Input
            VStack(spacing: MADTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
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
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: MADTheme.Spacing.md) {
                Button(action: onSubmit) {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text("Continue")
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
                
                if let onCancel = onCancel {
                    Button("Skip for now", action: onCancel)
                        .font(MADTheme.Typography.body)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
            }
        }
        .padding(MADTheme.Spacing.lg)
        .background(MADTheme.Colors.secondaryBackground)
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
        isValidating = true
        validationMessage = "Checking availability..."
        
        do {
            let isAvailable = try await UsernameService.checkAvailability(username)
            isValid = isAvailable
            validationMessage = isAvailable ? "Username is available!" : "Username is already taken"
        } catch {
            isValid = false
            validationMessage = "Unable to check username availability"
        }
        
        isValidating = false
    }
}

// MARK: - Requirement Row Component

struct RequirementRow: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? MADTheme.Colors.success : MADTheme.Colors.secondaryText)
                .font(.system(size: 12))
            
            Text(text)
                .font(MADTheme.Typography.caption)
                .foregroundColor(isMet ? MADTheme.Colors.success : MADTheme.Colors.secondaryText)
        }
    }
}

// MARK: - Username Service

class UsernameService {
    private static let backendURL = "https://mad.mindgoblin.tech"
    
    static func checkAvailability(_ username: String) async throws -> Bool {
        guard let url = URL(string: "\(backendURL)/users/check-username?username=\(username)") else {
            print("❌ UsernameService: Invalid URL")
            throw UsernameError.invalidURL
        }
        
        print("🔍 UsernameService: Checking availability for '\(username)'")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ UsernameService: Invalid response type")
                throw UsernameError.networkError
            }
            
            print("📡 UsernameService: Response status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ UsernameService: Server error \(httpResponse.statusCode): \(errorMessage)")
                
                // If it's a 404, it means username is available (not found)
                if httpResponse.statusCode == 404 {
                    print("✅ UsernameService: 404 means username is available")
                    return true
                }
                
                throw UsernameError.serverError
            }
            
            let result = try JSONDecoder().decode(UsernameAvailabilityResponse.self, from: data)
            print("✅ UsernameService: Username '\(username)' available: \(result.available)")
            return result.available
        } catch {
            print("❌ UsernameService: Network error: \(error.localizedDescription)")
            throw error
        }
    }
    
    static func updateUsername(_ username: String, userId: String, authToken: String) async throws {
        guard let url = URL(string: "\(backendURL)/users/\(userId)/username") else {
            throw UsernameError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let body = ["username": username]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsernameError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            _ = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UsernameError.serverError
        }
    }
}

// MARK: - Supporting Types

struct UsernameAvailabilityResponse: Codable {
    let available: Bool
}

enum UsernameError: Error, LocalizedError {
    case invalidURL
    case networkError
    case serverError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError:
            return "Network error occurred"
        case .serverError:
            return "Server error occurred"
        }
    }
}

#Preview {
    UsernameInputView(
        username: .constant(""),
        onSubmit: { print("Submit") },
        onCancel: { print("Cancel") }
    )
}
