import SwiftUI

struct WorkspaceSwitcherMenu: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Menu {
            ForEach(session.descriptors) { descriptor in
                Button {
                    session.switchToDescriptor(descriptor)
                } label: {
                    if descriptor.id == session.currentWorkspace?.id {
                        Label(descriptor.name, systemImage: "checkmark")
                    } else {
                        Text(descriptor.name)
                    }
                }
            }

            if !session.descriptors.isEmpty {
                Divider()
            }

            Button("New Workspace…") {
                session.present(.newWorkspace)
            }
            Button("Open Workspace…") {
                session.pickAndOpenWorkspace()
            }
        } label: {
            Label(session.currentWorkspace?.name ?? "Workspace", systemImage: "square.stack.3d.up")
        }
        .menuIndicator(.visible)
        .help("Switch workspace")
    }
}

#Preview {
    WorkspaceSwitcherMenu()
        .environment(AppSession.preview)
        .padding()
}
