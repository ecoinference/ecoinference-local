import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var profileService = UserProfileService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var bio = ""
    @State private var phoneNumber = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingAvatar: UIImage?
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Avatar") {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                            avatarLabel
                        }
                        .onChange(of: selectedPhoto) { _, item in
                            Task {
                                if let data = try? await item?.loadTransferable(type: Data.self),
                                   let img = UIImage(data: data) {
                                    pendingAvatar = img
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section("Display Name") {
                    TextField("Your name", text: $displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                }

                Section("Bio") {
                    TextField("A short bio…", text: $bio, axis: .vertical)
                        .lineLimit(3...5)
                }

                Section("Phone (optional)") {
                    TextField("Phone number", text: $phoneNumber)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isLoading || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadCurrent() }
        }
    }

    @ViewBuilder
    private var avatarLabel: some View {
        ZStack(alignment: .bottomTrailing) {
            if let img = pendingAvatar {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                AvatarView(urlString: profileService.profile?.avatarURL, size: 80)
            }
            Image(systemName: "pencil.circle.fill")
                .font(.title3)
                .foregroundStyle(EcoColors.green)
                .background(Circle().fill(EcoColors.background))
        }
    }

    private func loadCurrent() {
        displayName  = profileService.profile?.displayName ?? ""
        bio          = profileService.profile?.bio ?? ""
        phoneNumber  = profileService.profile?.phoneNumber ?? ""
    }

    private func save() async {
        guard let uid = authService.uid else { return }
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }
        do {
            var fields: [String: Any] = [
                "displayName": displayName.trimmingCharacters(in: .whitespaces),
                "bio":         bio.trimmingCharacters(in: .whitespaces),
                "phoneNumber": phoneNumber.trimmingCharacters(in: .whitespaces)
            ]
            if let img = pendingAvatar {
                fields["avatarURL"] = try await StorageService.shared.uploadAvatar(uid: uid, image: img)
            }
            try await profileService.updateProfile(uid: uid, fields: fields)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
