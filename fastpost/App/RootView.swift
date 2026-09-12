import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if session.hasOpenWorkspace {
                WorkspaceScreen()
            } else {
                OnboardingView()
            }
        }
        .frame(
            minWidth: session.hasOpenWorkspace ? 800 : 520,
            minHeight: session.hasOpenWorkspace ? 500 : 420
        )
        .alert(
            "Couldn't Complete Action",
            isPresented: Binding(
                get: { session.lastError != nil },
                set: { if !$0 { session.dismissError() } }
            ),
            presenting: session.lastError
        ) { _ in
            Button("OK", role: .cancel) {
                session.dismissError()
            }
        } message: { error in
            Text(error.localizedDescription)
        }
    }
}

#Preview("Onboarding") {
    RootView()
        .environment(AppSession.previewEmpty)
        .environment(RequestRuntime())
        .environment(ClientCertificateStore.preview)
        .environment(KeybindingStore.preview)
        .frame(width: 720, height: 520)
}

#Preview("Workspace") {
    RootView()
        .environment(AppSession.preview)
        .environment(RequestRuntime.preview)
        .environment(ClientCertificateStore.preview)
        .environment(KeybindingStore.preview)
        .frame(width: 1100, height: 740)
}
