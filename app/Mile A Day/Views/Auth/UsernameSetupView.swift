import SwiftUI

struct UsernameSetupView: View {
    @Environment(\.appStateManager) var appStateManager
    @EnvironmentObject var userManager: UserManager
    @State private var username = ""
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    MADTheme.Colors.madWhite,
                    MADTheme.Colors.secondaryBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            UsernameInputView(
                username: $username,
                onSubmit: handleUsernameSubmit,
                onCancel: handleSkip
            )
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
    
    private func handleSkip() {
        withAnimation(MADTheme.Animation.standard) {
            appStateManager.completeUsernameSetup()
        }
    }
}

#Preview {
    UsernameSetupView()
        .environmentObject(UserManager())
        .environmentObject(AppStateManager())
}
