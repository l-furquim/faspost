import SwiftUI

struct NewWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session

    var body: some View {
        NavigationStack {
            WorkspaceSetupForm { name, parentURL in
                session.createWorkspace(name: name, parentURL: parentURL)
                dismiss()
            }
            .padding(20)
            .navigationTitle("New Workspace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 320)
    }
}

#Preview {
    NewWorkspaceSheet()
        .environment(AppSession.previewEmpty)
}
