import SwiftUI

struct UsernameSetupView: View {
    @Environment(\.appStateManager) var appStateManager
    @EnvironmentObject var userManager: UserManager
    @State private var username = ""
    @State private var isValid = false
    @State private var reaction = 0
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        OnboardingFormScaffold(
            colors: [Color(red: 0.47, green: 0.36, blue: 0.95), Color(red: 0.20, green: 0.12, blue: 0.56)],
            headline: "Pick your username",
            message: "This is how friends find you, and how they'll pick you when you invite them.",
            art: { height in
                OnboardingFlamey(items: ["electric", "bow_tie"], size: min(height * 0.82, 130),
                                 line: isValid ? "Hi, @\(username)!" : nil, reaction: reaction)
                    .introPop(0.05)
            },
            content: {
                UsernameInputView(username: $username, isValid: $isValid, onSubmit: handleUsernameSubmit)
            },
            actions: {
                OnboardingPrimaryButton(
                    title: "Continue",
                    isLoading: isSubmitting,
                    isEnabled: isValid,
                    action: handleUsernameSubmit
                )
            }
        )
        .onChange(of: isValid) { _, valid in
            if valid { reaction += 1 }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func handleUsernameSubmit() {
        guard !username.isEmpty else { return }
        
        isSubmitting = true
        
        Task {
            do {
                // Update username in backend
                if let authToken = userManager.authToken,
                   let backendUserId = userManager.currentUser.backendUserId {
                    try await UsernameService.updateUsername(username, userId: backendUserId, authToken: authToken)
                }
                
                // Update local user
                await MainActor.run {
                    userManager.currentUser.username = username
                    userManager.saveUserData()
                    
                    withAnimation(MADTheme.Animation.standard) {
                        appStateManager.completeUsernameSetup()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSubmitting = false
                }
            }
        }
    }
    
}

#Preview {
    UsernameSetupView()
        .environmentObject(UserManager())
        .environmentObject(AppStateManager())
}
