import SwiftUI

struct EditProfileView: View {
    @ObservedObject var userManager: UserManager
    let onDismiss: () -> Void

    @State private var firstName: String
    @State private var lastName: String
    @State private var username: String
    @State private var bio: String
    @State private var selectedImageData: Data?
    @State private var pickedImage: UIImage?
    @State private var displayImage: UIImage?
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
            || selectedImageData != nil
    }

    private var canSave: Bool {
        hasChanges && !isSaving && !isValidatingUsername && isUsernameValid
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Profile Image
                    profileImageSection

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
                            .padding(.horizontal, MADTheme.Spacing.md)
                    }
                }
                .padding(MADTheme.Spacing.lg)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
            .background(MADTheme.Colors.secondaryBackground)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(MADTheme.Colors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(canSave ? MADTheme.Colors.madRed : MADTheme.Colors.secondaryText)
                    .disabled(!canSave)
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
                            selectedImageData = cropped.jpegData(compressionQuality: 0.8)
                            displayImage = cropped
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
                        .fill(MADTheme.Colors.redGradient)
                        .frame(width: 100, height: 100)

                    if let image = displayImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(.white)
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.black.opacity(0.7))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .frame(width: 100, height: 100)
                }
            }
            .buttonStyle(.plain)

            Text("Change Photo")
                .font(MADTheme.Typography.caption)
                .foregroundColor(MADTheme.Colors.madRed)
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Name")
                .font(MADTheme.Typography.headline)
                .foregroundColor(MADTheme.Colors.primaryText)

            HStack(spacing: MADTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                    Text("First")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    TextField("First name", text: $firstName)
                        .font(MADTheme.Typography.body)
                        .textFieldStyle(.plain)
                        .padding(MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(MADTheme.Colors.cardBackground)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                    Text("Last")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    TextField("Last name", text: $lastName)
                        .font(MADTheme.Typography.body)
                        .textFieldStyle(.plain)
                        .padding(MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(MADTheme.Colors.cardBackground)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: - Username Section

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Username")
                .font(MADTheme.Typography.headline)
                .foregroundColor(MADTheme.Colors.primaryText)

            HStack {
                Text("@")
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .padding(.leading, MADTheme.Spacing.md)

                TextField("Username", text: $username)
                    .font(MADTheme.Typography.body)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: username) { _, newValue in
                        validateUsername(newValue)
                    }
            }
            .padding(MADTheme.Spacing.md)
            .padding(.leading, -MADTheme.Spacing.md + 4)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(MADTheme.Colors.cardBackground)
                    .stroke(usernameBorderColor, lineWidth: 2)
            )

            if !usernameValidationMessage.isEmpty {
                HStack {
                    Image(systemName: usernameIcon)
                        .foregroundColor(usernameColor)
                    Text(usernameValidationMessage)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(usernameColor)
                }
            }
        }
    }

    // MARK: - Bio Section

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Bio")
                .font(MADTheme.Typography.headline)
                .foregroundColor(MADTheme.Colors.primaryText)

            TextField("Tell others about yourself...", text: $bio, axis: .vertical)
                .font(MADTheme.Typography.body)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .fill(MADTheme.Colors.cardBackground)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            Text("\(bio.count)/150 characters")
                .font(MADTheme.Typography.caption)
                .foregroundColor(bio.count > 150 ? MADTheme.Colors.error : MADTheme.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
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
                    await MainActor.run { displayImage = image }
                    return
                }
                // Fall back to local
                await MainActor.run { displayImage = getLocalProfileImage() }
            }
        } else {
            displayImage = getLocalProfileImage()
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
                if let imageData = selectedImageData, let image = UIImage(data: imageData) {
                    let imageUrl = try await ProfileImageService.uploadProfileImage(image, userId: backendUserId)
                    await MainActor.run {
                        userManager.currentUser.profileImageUrl = imageUrl
                        // Also save locally for fast access
                        UserDefaults.standard.set(imageData, forKey: "customProfileImage")
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
