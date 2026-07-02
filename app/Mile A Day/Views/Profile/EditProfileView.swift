import SwiftUI

struct EditProfileView: View {
    @ObservedObject var userManager: UserManager
    let onDismiss: () -> Void

    @State private var firstName: String
    @State private var lastName: String
    @State private var username: String
    @State private var bio: String
    @State private var selectedImage: UIImage?
    @State private var pickedImage: UIImage?
    @State private var currentProfileImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCropper = false
    @State private var isSaving = false
    @State private var saveError: String?

    // Username validation
    @State private var isValidatingUsername = false
    @State private var usernameValidationMessage = ""
    @State private var isUsernameValid = true
    @State private var usernameValidationTimer: Timer?

    init(userManager: UserManager, onDismiss: @escaping () -> Void) {
        self.userManager = userManager
        self.onDismiss = onDismiss
        let user = userManager.currentUser
        self._firstName = State(initialValue: user.firstName ?? "")
        self._lastName = State(initialValue: user.lastName ?? "")
        self._username = State(initialValue: user.username ?? "")
        self._bio = State(initialValue: user.bio ?? "")
    }

    private var originalUsername: String {
        userManager.currentUser.username ?? ""
    }

    private var hasChanges: Bool {
        let user = userManager.currentUser
        return firstName != (user.firstName ?? "")
            || lastName != (user.lastName ?? "")
            || username != (user.username ?? "")
            || bio != (user.bio ?? "")
            || selectedImage != nil
    }

    private var canSave: Bool {
        hasChanges && !isSaving && !isValidatingUsername && isUsernameValid
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Full-bleed app backdrop — this is a real screen, not a form card.
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        // Profile Image
                        profileImageSection
                            .padding(.top, MADTheme.Spacing.md)

                        // Name Fields
                        nameSection

                        // Username
                        usernameSection

                        // Bio
                        bioSection

                        // Error
                        if let error = saveError {
                            Text(error)
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(MADTheme.Colors.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, MADTheme.Spacing.md)
                        }
                    }
                    .padding(MADTheme.Spacing.lg)
                    .padding(.bottom, MADTheme.Spacing.xl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Button("Save") {
                            saveProfile()
                        }
                        .fontWeight(.bold)
                        .foregroundColor(canSave ? MADTheme.Colors.madRed : .white.opacity(0.3))
                        .disabled(!canSave)
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $pickedImage)
            }
            .fullScreenCover(isPresented: $showingCropper) {
                if let image = pickedImage {
                    ProfileImageCropper(
                        image: image,
                        onCrop: { cropped in
                            selectedImage = cropped
                            currentProfileImage = cropped
                            showingCropper = false
                            pickedImage = nil
                        },
                        onCancel: {
                            showingCropper = false
                            pickedImage = nil
                        }
                    )
                }
            }
            .onChange(of: pickedImage) { _, newImage in
                if newImage != nil {
                    showingCropper = true
                }
            }
            .onAppear {
                loadCurrentProfileImage()
            }
        }
    }

    // MARK: - Profile Image Section

    private var profileImageSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Button(action: { showingImagePicker = true }) {
                ZStack {
                    Circle()
                        .strokeBorder(MADTheme.Colors.redGradient, lineWidth: 3)
                        .frame(width: 122, height: 122)
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.35), radius: 14, y: 4)

                    if let image = currentProfileImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                    } else {
                        AvatarView(name: userManager.currentUser.name, imageURL: userManager.currentUser.profileImageUrl, size: 110)
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(MADTheme.Colors.madRed)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                )
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
                        }
                    }
                    .frame(width: 116, height: 116)
                }
            }
            .buttonStyle(.plain)

            Text("Change Photo")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(MADTheme.Colors.madRed)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dark form styling

    /// Section label in the app's editor style (caps, dimmed, tracked).
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.45))
    }

    /// Dark rounded field backdrop shared by every input on this screen.
    private func fieldBackground(stroke: Color = Color.white.opacity(0.12)) -> some View {
        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .stroke(stroke, lineWidth: 1)
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionLabel("NAME")

            HStack(spacing: MADTheme.Spacing.md) {
                TextField("", text: $firstName, prompt: Text("First name").foregroundColor(.white.opacity(0.35)))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .padding(MADTheme.Spacing.md)
                    .background(fieldBackground())

                TextField("", text: $lastName, prompt: Text("Last name").foregroundColor(.white.opacity(0.35)))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .padding(MADTheme.Spacing.md)
                    .background(fieldBackground())
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Username Section

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionLabel("USERNAME")

            HStack(spacing: 4) {
                Text("@")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))

                TextField("", text: $username, prompt: Text("username").foregroundColor(.white.opacity(0.35)))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: username) { _, newValue in
                        validateUsername(newValue)
                    }
            }
            .padding(MADTheme.Spacing.md)
            .background(fieldBackground(stroke: usernameBorderColor))

            if !usernameValidationMessage.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: usernameIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(usernameColor)
                    Text(usernameValidationMessage)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(usernameColor)
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Bio Section

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            sectionLabel("BIO")

            TextField(
                "",
                text: $bio,
                prompt: Text("Tell others about yourself…").foregroundColor(.white.opacity(0.35)),
                axis: .vertical
            )
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundColor(.white)
            .textFieldStyle(.plain)
            .lineLimit(3...6)
            .padding(MADTheme.Spacing.md)
            .background(fieldBackground())

            Text("\(bio.count)/150")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(bio.count > 150 ? MADTheme.Colors.error : .white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Username Validation

    private var usernameBorderColor: Color {
        if isValidatingUsername { return MADTheme.Colors.warning }
        if isUsernameValid && !username.isEmpty { return MADTheme.Colors.success }
        if !usernameValidationMessage.isEmpty && !isUsernameValid { return MADTheme.Colors.error }
        return Color.gray.opacity(0.3)
    }

    private var usernameColor: Color {
        if isValidatingUsername { return MADTheme.Colors.warning }
        if isUsernameValid { return MADTheme.Colors.success }
        return MADTheme.Colors.error
    }

    private var usernameIcon: String {
        if isValidatingUsername { return "clock" }
        if isUsernameValid { return "checkmark.circle.fill" }
        return "exclamationmark.circle.fill"
    }

    private func validateUsername(_ value: String) {
        usernameValidationTimer?.invalidate()

        if value.isEmpty {
            usernameValidationMessage = ""
            isUsernameValid = false
            return
        }

        // Basic requirements
        if value.count < 3 {
            usernameValidationMessage = "Must be at least 3 characters"
            isUsernameValid = false
            return
        }
        if value.count > 20 {
            usernameValidationMessage = "Must be 20 characters or less"
            isUsernameValid = false
            return
        }
        if !value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
            usernameValidationMessage = "Only letters, numbers, and underscores"
            isUsernameValid = false
            return
        }
        if let first = value.first, !first.isLetter {
            usernameValidationMessage = "Must start with a letter"
            isUsernameValid = false
            return
        }

        // Same as current - no server check needed
        if value == originalUsername {
            usernameValidationMessage = ""
            isUsernameValid = true
            return
        }

        // Debounced server check
        usernameValidationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            Task { @MainActor in
                isValidatingUsername = true
                usernameValidationMessage = "Checking..."
                do {
                    let available = try await UsernameService.checkAvailability(value)
                    isUsernameValid = available
                    usernameValidationMessage = available ? "Available" : "Already taken"
                } catch {
                    isUsernameValid = true
                    usernameValidationMessage = ""
                }
                isValidatingUsername = false
            }
        }
    }

    // MARK: - Actions

    private func loadCurrentProfileImage() {
        // Try loading from server URL first, then fall back to local
        if let urlPath = userManager.currentUser.profileImageUrl,
           let url = ProfileImageService.fullImageURL(for: urlPath) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    await MainActor.run { currentProfileImage = image }
                    return
                }
                // Fall back to local
                await MainActor.run { currentProfileImage = getLocalProfileImage() }
            }
        } else {
            currentProfileImage = getLocalProfileImage()
        }
    }

    private func getLocalProfileImage() -> UIImage? {
        if let data = UserDefaults.standard.data(forKey: "customProfileImage"),
           let image = UIImage(data: data) {
            return image
        }
        return userManager.getAppleProfileImage()
    }

    private func saveProfile() {
        isSaving = true
        saveError = nil

        Task {
            do {
                guard let backendUserId = userManager.currentUser.backendUserId
                    ?? UserDefaults.standard.string(forKey: "backendUserId") else {
                    await MainActor.run {
                        saveError = "Please sign out and sign back in to edit your profile"
                        isSaving = false
                    }
                    return
                }

                // Upload image if changed
                if let image = selectedImage {
                    let imageUrl = try await ProfileImageService.uploadProfileImage(image, userId: backendUserId)
                    await MainActor.run {
                        userManager.currentUser.profileImageUrl = imageUrl
                        // Also save locally for fast access
                        if let data = image.jpegData(compressionQuality: 0.8) {
                            UserDefaults.standard.set(data, forKey: "customProfileImage")
                        }
                    }
                }

                // Build update body for text fields
                var updates: [String: Any] = [:]
                let user = userManager.currentUser

                if firstName != (user.firstName ?? "") {
                    updates["first_name"] = firstName.isEmpty ? NSNull() : firstName
                }
                if lastName != (user.lastName ?? "") {
                    updates["last_name"] = lastName.isEmpty ? NSNull() : lastName
                }
                if username != (user.username ?? "") && !username.isEmpty {
                    updates["username"] = username
                }
                if bio != (user.bio ?? "") {
                    updates["bio"] = bio
                }

                if !updates.isEmpty {
                    let bodyData = try JSONSerialization.data(withJSONObject: updates)

                    struct UpdateResponse: Codable {
                        let user_id: String
                        let username: String?
                        let first_name: String?
                        let last_name: String?
                        let bio: String?
                        let profile_image_url: String?
                    }

                    let _: UpdateResponse = try await APIClient.fancyFetch(
                        endpoint: "/users/\(backendUserId)",
                        method: .PATCH,
                        body: bodyData,
                        responseType: UpdateResponse.self
                    )
                }

                // Update local state
                await MainActor.run {
                    userManager.currentUser.firstName = firstName.isEmpty ? nil : firstName
                    userManager.currentUser.lastName = lastName.isEmpty ? nil : lastName
                    if !username.isEmpty {
                        userManager.currentUser.username = username
                    }
                    userManager.currentUser.bio = bio.isEmpty ? nil : bio
                    userManager.saveUserData()
                    isSaving = false
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    saveError = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

#Preview {
    EditProfileView(
        userManager: UserManager(),
        onDismiss: { }
    )
}
