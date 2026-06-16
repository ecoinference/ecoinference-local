import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var profileService = UserProfileService.shared
    @State private var showEdit = false
    @State private var showSignOutAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        AvatarView(urlString: profileService.profile?.avatarURL, size: 60)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profileService.profile?.displayName ?? "—")
                                .font(.headline)
                            Text("@\(profileService.profile?.username ?? "")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if let bio = profileService.profile?.bio, !bio.isEmpty {
                    Section("Bio") {
                        Text(bio)
                    }
                }

                Section("Account") {
                    LabeledContent("Email") {
                        Text(authService.email ?? "")
                            .foregroundStyle(.secondary)
                    }
                    if let phone = profileService.profile?.phoneNumber, !phone.isEmpty {
                        LabeledContent("Phone") {
                            Text(phone).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }
                }
            }
            .sheet(isPresented: $showEdit) {
                EditProfileView()
                    .environmentObject(authService)
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Sign Out", role: .destructive) {
                    try? authService.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
}

// MARK: - Shared avatar helper

struct AvatarView: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let str = urlString, let url = URL(string: str) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(EcoColors.green)
    }
}
