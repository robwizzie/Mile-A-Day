import SwiftUI

struct UsernameInputView: View {
    @Binding var username: String
    @State private var isValidating = false
    @State private var validationMessage = ""
    @Binding var isValid: Bool
    @State private var validationTimer: Timer?
    
    let onSubmit: () -> Void
    let onCancel: (() -> Void)?
    
    init(username: Binding<String>, isValid: Binding<Bool>, onSubmit: @escaping () -> Void, onCancel: (() -> Void)? = nil) {
        self._username = username
        self._isValid = isValid
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }
    
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: 4) {
                Text("@")
                    .madFont(size: 17, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.5))
                TextField("", text: $username, prompt: Text("username").foregroundColor(.white.opacity(0.35)))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isTextFieldFocused)
                    .onSubmit { isTextFieldFocused = false }
                    .onChange(of: username) { _, newValue in
                        validateUsername(newValue)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(validationBorderColor, lineWidth: 1.5)
                    )
            )

            if !validationMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: validationIcon)
                        .accessibilityHidden(true)
                    Text(validationMessage)
                        .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.3)
                }
                .foregroundColor(validationColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                RequirementRow(text: "3 to 20 characters", isMet: username.count >= 3 && username.count <= 20)
                RequirementRow(
                    text: "Letters, numbers and underscores",
                    isMet: !username.isEmpty && username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
                )
                RequirementRow(text: "Starts with a letter", isMet: username.first?.isLetter == true)
                RequirementRow(text: "Available", isMet: isValid && !isValidating)
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
        HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? MADTheme.Colors.success : MADTheme.Colors.secondaryText)
                .font(.system(size: 12))

            Text(text)
                .font(MADTheme.Typography.caption)
                .foregroundColor(isMet ? MADTheme.Colors.success : MADTheme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Username Service

class UsernameService {
    private static let backendURL = AppConfig.baseURL
    
    static func checkAvailability(_ username: String) async throws -> Bool {
        guard let url = URL(string: "\(backendURL)/users/check-username?username=\(username)") else {
            throw UsernameError.invalidURL
        }

        do {
            var request = URLRequest(url: url)
            if let token = UserDefaults.standard.string(forKey: "authToken") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw UsernameError.networkError
            }
            
            guard httpResponse.statusCode == 200 else {
                // If it's a 404, it means username is available (not found)
                if httpResponse.statusCode == 404 {
                    return true
                }
                
                throw UsernameError.serverError
            }
            
            let result = try JSONDecoder().decode(UsernameAvailabilityResponse.self, from: data)
            return result.available
        } catch {
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
        isValid: .constant(false),
        onSubmit: { },
        onCancel: { }
    )
}
