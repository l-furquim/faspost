import SwiftUI

@main
struct FastpostApp: App {
    @State private var session = AppSession()
    @State private var certificates: ClientCertificateStore
    @State private var runtime: RequestRuntime
    @State private var keybindings = KeybindingStore()
    @AppStorage(AppearanceStorage.colorSchemeKey) private var colorSchemeRaw = ColorSchemePreference.system.rawValue
    @AppStorage(AppearanceStorage.themeIDKey) private var themeID = AppThemeID.default.rawValue

    init() {
        let certificates = ClientCertificateStore()
        let runtime = RequestRuntime()
        runtime.certificates = certificates
        _certificates = State(initialValue: certificates)
        _runtime = State(initialValue: runtime)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(runtime)
                .environment(certificates)
                .environment(keybindings)
                .environment(\.appTheme, AppTheme.named(themeID))
                .appThemeChrome(
                    appearance: ColorSchemePreference(rawValue: colorSchemeRaw)?.preferredColorScheme
                )
        }
        .defaultSize(width: 1100, height: 740)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            WorkspaceCommands(session: session, runtime: runtime, keybindings: keybindings)
        }

        Settings {
            TabView {
                Tab("General", systemImage: "gearshape") {
                    GeneralSettingsView()
                        .scenePadding()
                }
                Tab("Shortcuts", systemImage: "command") {
                    ShortcutsSettingsView()
                        .scenePadding()
                }
                Tab("Certificates", systemImage: "lock.doc") {
                    CertificatesSettingsView()
                }
                Tab("Editor", systemImage: "chevron.left.forwardslash.chevron.right") {
                    EditorSettingsView()
                        .scenePadding()
                }
                Tab("Appearance", systemImage: "paintpalette") {
                    AppearanceSettingsView()
                        .scenePadding()
                }
            }
            .environment(certificates)
            .environment(keybindings)
            .environment(\.appTheme, AppTheme.named(themeID))
            .appThemeChrome(
                appearance: ColorSchemePreference(rawValue: colorSchemeRaw)?.preferredColorScheme
            )
            .frame(minWidth: 780, minHeight: 560)
        }
        .defaultSize(width: 820, height: 600)
    }
}
