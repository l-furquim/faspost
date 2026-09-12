import SwiftUI

struct CommandPaletteOverlay: View {
    @Environment(\.appTheme) private var theme
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Group {
                if let chrome = theme.chrome {
                    chrome.window.opacity(0.42)
                } else {
                    Color.black.opacity(0.08)
                }
            }
            .ignoresSafeArea()
            .onTapGesture {
                isPresented = false
            }

            CommandPaletteView(isPresented: $isPresented)
                .frame(width: 560)
                .frame(maxHeight: 460, alignment: .top)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

struct CommandPaletteView: View {
    @Environment(AppSession.self) private var session
    @Environment(RequestRuntime.self) private var runtime
    @Environment(KeybindingStore.self) private var keybindings
    @Environment(\.appTheme) private var theme

    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selection: PaletteRow.ID?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CommandPaletteSearchField(query: $query, isSearchFocused: $isSearchFocused)
                .onSubmit(executeSelection)
                .onKeyPress(.downArrow) {
                    moveSelection(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(-1)
                    return .handled
                }

            if rows.isEmpty {
                Text("No Results")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if !commands.isEmpty {
                            CommandPaletteSection(title: "Commands") {
                                ForEach(commands) { row in
                                    CommandPaletteRowButton(
                                        row: row,
                                        theme: theme,
                                        shortcutGlyphs: row.commandID.flatMap { keybindings.glyphs(for: $0) },
                                        isSelected: selection == row.id,
                                        action: { activate(row) },
                                        hover: { selection = row.id }
                                    )
                                }
                            }
                        }
                        if !requests.isEmpty {
                            CommandPaletteSection(title: "Requests") {
                                ForEach(requests) { row in
                                    CommandPaletteRowButton(
                                        row: row,
                                        theme: theme,
                                        shortcutGlyphs: row.commandID.flatMap { keybindings.glyphs(for: $0) },
                                        isSelected: selection == row.id,
                                        action: { activate(row) },
                                        hover: { selection = row.id }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 360)
            }
        }
        .modifier(CommandPaletteChrome())
        .onAppear {
            isSearchFocused = true
            selection = rows.first?.id
        }
        .onChange(of: query) { _, _ in
            let visible = rows
            if let selection, visible.contains(where: { $0.id == selection }) {
                return
            }
            self.selection = visible.first?.id
        }
        .onExitCommand {
            isPresented = false
        }
    }

    private var performer: AppCommandPerformer {
        AppCommandPerformer(session: session, runtime: runtime)
    }

    private var commands: [PaletteRow] {
        AppCommandCatalog.paletteCommands.compactMap { command in
            guard matches(String(localized: command.title)) else { return nil }
            return .command(command, isEnabled: performer.isEnabled(command.id))
        }
    }

    private var requests: [PaletteRow] {
        session.collectionItems.flattenedRequests().compactMap { entry in
            let haystack = ([entry.item.displayName, entry.item.method?.rawValue ?? "", entry.item.request?.rawURL ?? ""] + entry.path)
                .joined(separator: " ")
            guard matches(haystack) else { return nil }
            return .request(entry.item, path: entry.path, isEnabled: true)
        }
    }

    private var rows: [PaletteRow] {
        commands + requests
    }

    private func matches(_ text: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty || text.localizedStandardContains(needle)
    }

    private func moveSelection(_ delta: Int) {
        let visible = rows
        guard !visible.isEmpty else { return }
        let current = selection.flatMap { id in visible.firstIndex(where: { $0.id == id }) } ?? 0
        let next = min(max(current + delta, 0), visible.count - 1)
        selection = visible[next].id
    }

    private func executeSelection() {
        let visible = rows
        guard let selection, let row = visible.first(where: { $0.id == selection }) else {
            return
        }
        activate(row)
    }

    private func activate(_ row: PaletteRow) {
        switch row {
        case .command(let command, let isEnabled):
            guard isEnabled else { return }
            isPresented = false
            performer.perform(command.id)
        case .request(let item, _, _):
            session.revealItem(id: item.id)
            isPresented = false
        }
    }
}

private struct CommandPaletteSearchField: View {
    @Binding var query: String
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused(isSearchFocused)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private struct CommandPaletteSection<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)
            content
        }
    }
}

private struct CommandPaletteRowButton: View {
    let row: PaletteRow
    let theme: AppTheme
    let shortcutGlyphs: String?
    let isSelected: Bool
    let action: () -> Void
    let hover: () -> Void

    var body: some View {
        Button(action: action) {
            CommandPaletteRowLabel(row: row, theme: theme, shortcutGlyphs: shortcutGlyphs, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!row.isEnabled)
        .onHover { hovering in
            if hovering {
                hover()
            }
        }
    }
}

private struct CommandPaletteRowLabel: View {
    let row: PaletteRow
    let theme: AppTheme
    let shortcutGlyphs: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            leading
            titles
            Spacer(minLength: 8)
            if let glyphs = shortcutGlyphs {
                Text(verbatim: glyphs)
                    .font(.caption.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.55), in: Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .opacity(row.isEnabled ? 1 : 0.45)
    }

    @ViewBuilder
    private var leading: some View {
        switch row {
        case .command(let command, _):
            Image(systemName: command.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .request(let item, _, _):
            Text(item.method?.rawValue ?? "GET")
                .font(.caption2.weight(.semibold).monospaced())
                .foregroundStyle(theme.method.color(for: item.method ?? .get))
                .frame(width: 36, height: 28)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    @ViewBuilder
    private var titles: some View {
        switch row {
        case .command(let command, _):
            Text(command.title)
                .foregroundStyle(.primary)
        case .request(let item, let path, _):
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                if !path.isEmpty {
                    Text(path.joined(separator: " / "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CommandPaletteChrome: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        if let chrome = theme.chrome {
            content
                .background(chrome.surface, in: shape)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(chrome.accent.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 36, y: 14)
        } else if #available(macOS 26, *) {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.16), radius: 36, y: 14)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.16), radius: 36, y: 14)
        }
    }
}

private enum PaletteRow: Identifiable {
    case command(AppCommandDefinition, isEnabled: Bool)
    case request(CollectionItem, path: [String], isEnabled: Bool)

    var id: String {
        switch self {
        case .command(let command, _):
            "command.\(command.id.rawValue)"
        case .request(let item, _, _):
            "request.\(item.id)"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .command(_, let isEnabled), .request(_, _, let isEnabled):
            isEnabled
        }
    }

    var commandID: AppCommandID? {
        switch self {
        case .command(let command, _):
            command.id
        case .request:
            nil
        }
    }
}

#Preview {
    CommandPaletteOverlay(isPresented: .constant(true))
        .environment(AppSession.preview)
        .environment(RequestRuntime.preview)
        .environment(KeybindingStore.preview)
        .frame(width: 720, height: 520)
}
