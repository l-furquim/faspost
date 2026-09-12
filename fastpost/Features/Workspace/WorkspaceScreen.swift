import SwiftUI

struct WorkspaceScreen: View {
    @Environment(AppSession.self) private var session
    @State private var isCommandPalettePresented = false

    var body: some View {
        @Bindable var session = session

        NavigationSplitView {
            WorkspaceSidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            RequestEditorView()
                .appThemeSurface()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                WorkspaceSwitcherMenu()
            }
            ToolbarItem(placement: .primaryAction) {
                EnvironmentSwitcherMenu()
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    isCommandPalettePresented = true
                } label: {
                    Label("Commands", systemImage: "magnifyingglass")
                }
                .help("Commands")
                .appShortcut(.commandPalette)
            }
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .overlay {
            if isCommandPalettePresented {
                CommandPaletteOverlay(isPresented: $isCommandPalettePresented)
            }
        }
        .animation(.smooth(duration: 0.2), value: isCommandPalettePresented)
        .focusedSceneValue(\.isCommandPalettePresented, $isCommandPalettePresented)
        .sheet(item: $session.presentedSheet) { sheet in
            Group {
                switch sheet {
                case .newWorkspace:
                    NewWorkspaceSheet()
                case .environments:
                    EnvironmentsSheet()
                }
            }
            .appThemePresentationBackground()
        }
    }
}

#Preview("Workspace") {
    WorkspaceScreen()
        .environment(AppSession.preview)
        .environment(RequestRuntime.preview)
        .environment(ClientCertificateStore.preview)
        .environment(KeybindingStore.preview)
        .frame(width: 1100, height: 740)
}
