import SwiftUI

struct OnboardingView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 10) {
                Image(systemName: "bolt.horizontal")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
                Text("Welcome to Fastpost")
                    .font(.largeTitle.weight(.semibold))
                Text("Create a workspace to organize collections, folders, and requests.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            WorkspaceSetupForm { name, parentURL in
                session.createWorkspace(name: name, parentURL: parentURL)
            }
            .frame(maxWidth: 400)

            Button("Open Existing Workspace…") {
                session.pickAndOpenWorkspace()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appThemeSurface()
    }
}

#Preview("Onboarding") {
    OnboardingView()
        .environment(AppSession.previewEmpty)
        .frame(width: 720, height: 520)
}
