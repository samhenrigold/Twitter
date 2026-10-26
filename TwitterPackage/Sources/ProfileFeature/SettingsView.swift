import ColumnNavigation
import ComposableArchitecture
import FeedFeature
import Models
import SwiftUI
import TwitterUI

/// Settings, from your own profile: the account you're signed in with, how Tweets look, sounds, and about the app.
struct SettingsView: View {
    let store: StoreOf<ProfileFeature>
    @Shared(.postRowStyle) private var postRowStyle
    @Shared(.appStorage(ClassicSound.settingKey)) private var playsSounds = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let viewer = store.user {
                    Section("Account") {
                        HStack(spacing: 12) {
                            Avatar(user: viewer, size: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewer.name)
                                    .font(.body.weight(.bold))

                                Text(verbatim: "@\(viewer.screenName)")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button("Sign Out", twitterIcon: .signOut, role: .destructive) {
                            dismiss()
                            store.send(.signOutButtonTapped)
                        }
                    }
                }

                Section {
                    Picker("Tweet Layout", selection: Binding($postRowStyle)) {
                        ForEach(PostRowStyle.allCases, id: \.self) { style in
                            Text(style.title)
                        }
                    }

                    Toggle("Sounds", isOn: Binding($playsSounds))
                } header: {
                    Text("Display and Sound")
                } footer: {
                    Text("Sounds play as you pull a timeline to refresh, as in Twitter for iPad.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                }

                #if DEBUG
                    Section("Debug") {
                        NavigationLink("Columns") {
                            ColumnDebugPanel()
                                .navigationTitle("Columns")
                                .ignoresSafeArea()
                        }
                    }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#if DEBUG
    /// The column stack's live tuning, from the prototype.
    private struct ColumnDebugPanel: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> ColumnDebugPanelViewController {
            ColumnDebugPanelViewController()
        }

        func updateUIViewController(_ controller: ColumnDebugPanelViewController, context: Context) {}
    }
#endif
