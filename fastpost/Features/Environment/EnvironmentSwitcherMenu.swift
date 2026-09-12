import SwiftUI

struct EnvironmentSwitcherMenu: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Menu {
            Button {
                session.selectEnvironment(id: nil)
            } label: {
                if session.activeEnvironmentID == nil {
                    Label("No Environment", systemImage: "checkmark")
                } else {
                    Text("No Environment")
                }
            }

            if !session.environments.isEmpty {
                Divider()
                ForEach(session.environments) { environment in
                    Button {
                        session.selectEnvironment(id: environment.id)
                    } label: {
                        if environment.id == session.activeEnvironmentID {
                            Label(environment.name, systemImage: "checkmark")
                        } else {
                            Text(environment.name)
                        }
                    }
                }
            }

            Divider()
            Button("Manage Environments…") {
                session.present(.environments)
            }
        } label: {
            Label(activeName, systemImage: "server.rack")
                .labelStyle(.titleAndIcon)
        }
        .menuIndicator(.visible)
        .help(activeName)
        .disabled(!session.hasOpenWorkspace)
    }

    private var activeName: String {
        session.activeEnvironment?.name ?? String(localized: "No Environment")
    }
}

#Preview {
    EnvironmentSwitcherMenu()
        .environment(AppSession.preview)
        .padding()
}
