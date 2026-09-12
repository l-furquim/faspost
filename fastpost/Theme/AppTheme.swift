import AppKit
import SwiftUI

struct AppTheme: Equatable {
    var status: Status
    var method: Method
    var syntax: Syntax
    var variable: Variable
    var editorBackground: Color
    var chrome: Chrome?

    struct Chrome: Equatable {
        var window: Color
        var sidebar: Color
        var surface: Color
        var accent: Color
        var colorScheme: ColorScheme
    }

    var usesSystemChrome: Bool { chrome == nil }

    struct Status: Equatable {
        var informational: Color
        var success: Color
        var redirect: Color
        var clientError: Color
        var serverError: Color
        var unknown: Color

        func color(for family: StatusFamily) -> Color {
            switch family {
            case .informational: informational
            case .success: success
            case .redirect: redirect
            case .clientError: clientError
            case .serverError: serverError
            case .unknown: unknown
            }
        }
    }

    struct Method: Equatable {
        var get: Color
        var post: Color
        var put: Color
        var patch: Color
        var delete: Color
        var other: Color

        func color(for method: HTTPMethod) -> Color {
            switch method {
            case .get: get
            case .post: post
            case .put: put
            case .patch: patch
            case .delete: delete
            case .head, .options: other
            }
        }
    }

    struct Syntax: Equatable {
        var text: Color
        var key: Color
        var string: Color
        var number: Color
        var keyword: Color
        var punctuation: Color
    }

    struct Variable: Equatable {
        var resolved: Color
        var unresolved: Color
    }

    static let `default` = AppTheme(
        status: Status(
            informational: .blue,
            success: .green,
            redirect: .orange,
            clientError: .red,
            serverError: .red,
            unknown: .secondary
        ),
        method: Method(
            get: .green,
            post: .orange,
            put: .blue,
            patch: .purple,
            delete: .red,
            other: .secondary
        ),
        syntax: Syntax(
            text: .primary,
            key: .teal,
            string: .green,
            number: .orange,
            keyword: .purple,
            punctuation: .secondary
        ),
        variable: Variable(
            resolved: .teal,
            unresolved: .orange
        ),
        editorBackground: Color.primary.opacity(0.04),
        chrome: nil
    )

    static let oneDark = coded(
        background: "282C34",
        sidebar: "21252B",
        text: "ABB2BF",
        muted: "5C6370",
        red: "E06C75",
        orange: "D19A66",
        yellow: "E5C07B",
        green: "98C379",
        cyan: "56B6C2",
        blue: "61AFEF",
        purple: "C678DD",
        key: "E06C75"
    )

    static let dracula = coded(
        background: "282A36",
        sidebar: "21222C",
        text: "F8F8F2",
        muted: "6272A4",
        red: "FF5555",
        orange: "FFB86C",
        yellow: "F1FA8C",
        green: "50FA7B",
        cyan: "8BE9FD",
        blue: "BD93F9",
        purple: "BD93F9",
        keyword: "FF79C6"
    )

    static let nord = coded(
        background: "2E3440",
        sidebar: "3B4252",
        text: "ECEFF4",
        muted: "4C566A",
        red: "BF616A",
        orange: "D08770",
        yellow: "EBCB8B",
        green: "A3BE8C",
        cyan: "88C0D0",
        blue: "5E81AC",
        purple: "B48EAD"
    )

    static let tokyoNight = coded(
        background: "1A1B26",
        sidebar: "16161E",
        text: "C0CAF5",
        muted: "565F89",
        red: "F7768E",
        orange: "FF9E64",
        yellow: "E0AF68",
        green: "9ECE6A",
        cyan: "7DCFFF",
        blue: "7AA2F7",
        purple: "BB9AF7"
    )

    static let monokai = coded(
        background: "272822",
        sidebar: "1E1F1C",
        text: "F8F8F2",
        muted: "75715E",
        red: "F92672",
        orange: "FD971F",
        yellow: "E6DB74",
        green: "A6E22E",
        cyan: "66D9EF",
        blue: "66D9EF",
        purple: "AE81FF",
        keyword: "F92672"
    )

    static let catppuccinMocha = coded(
        background: "1E1E2E",
        sidebar: "181825",
        text: "CDD6F4",
        muted: "6C7086",
        red: "F38BA8",
        orange: "FAB387",
        yellow: "F9E2AF",
        green: "A6E3A1",
        cyan: "94E2D5",
        blue: "89B4FA",
        purple: "CBA6F7"
    )

    static let solarizedDark = coded(
        background: "002B36",
        sidebar: "073642",
        text: "839496",
        muted: "586E75",
        red: "DC322F",
        orange: "CB4B16",
        yellow: "B58900",
        green: "859900",
        cyan: "2AA198",
        blue: "268BD2",
        purple: "6C71C4"
    )

    private static func coded(
        background: String,
        sidebar: String,
        text: String,
        muted: String,
        red: String,
        orange: String,
        yellow: String,
        green: String,
        cyan: String,
        blue: String,
        purple: String,
        key: String? = nil,
        keyword: String? = nil
    ) -> AppTheme {
        let keywordColor = Color(hex: keyword ?? purple)
        let window = Color(hex: background)
        return AppTheme(
            status: Status(
                informational: Color(hex: blue),
                success: Color(hex: green),
                redirect: Color(hex: orange),
                clientError: Color(hex: red),
                serverError: Color(hex: red),
                unknown: Color(hex: muted)
            ),
            method: Method(
                get: Color(hex: green),
                post: Color(hex: orange),
                put: Color(hex: blue),
                patch: keywordColor,
                delete: Color(hex: red),
                other: Color(hex: muted)
            ),
            syntax: Syntax(
                text: Color(hex: text),
                key: Color(hex: key ?? cyan),
                string: Color(hex: green),
                number: Color(hex: orange),
                keyword: keywordColor,
                punctuation: Color(hex: muted)
            ),
            variable: Variable(
                resolved: Color(hex: cyan),
                unresolved: Color(hex: yellow)
            ),
            editorBackground: window,
            chrome: Chrome(
                window: window,
                sidebar: Color(hex: sidebar),
                surface: window,
                accent: Color(hex: blue),
                colorScheme: .dark
            )
        )
    }
}

extension AppTheme {
    static func named(_ id: String) -> AppTheme {
        AppThemeID(rawValue: id)?.theme ?? .default
    }
}

enum AppThemeID: String, CaseIterable, Identifiable {
    case `default`
    case oneDark
    case dracula
    case nord
    case tokyoNight
    case monokai
    case catppuccinMocha
    case solarizedDark

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .default: "Default"
        case .oneDark: "One Dark"
        case .dracula: "Dracula"
        case .nord: "Nord"
        case .tokyoNight: "Tokyo Night"
        case .monokai: "Monokai"
        case .catppuccinMocha: "Catppuccin Mocha"
        case .solarizedDark: "Solarized Dark"
        }
    }

    var theme: AppTheme {
        switch self {
        case .default: .default
        case .oneDark: .oneDark
        case .dracula: .dracula
        case .nord: .nord
        case .tokyoNight: .tokyoNight
        case .monokai: .monokai
        case .catppuccinMocha: .catppuccinMocha
        case .solarizedDark: .solarizedDark
        }
    }
}

enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppearanceStorage {
    static let colorSchemeKey = "appearance.colorScheme"
    static let themeIDKey = "appearance.themeID"
}

extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .default
}

struct ThemedSceneModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    var appearance: ColorScheme?

    func body(content: Content) -> some View {
        if let chrome = theme.chrome {
            content
                .tint(chrome.accent)
                .preferredColorScheme(chrome.colorScheme)
                .containerBackground(chrome.window, for: .window)
                .toolbarBackground(chrome.window, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
                .background {
                    WindowChromeApplicator(color: NSColor(chrome.window))
                }
        } else {
            content
                .preferredColorScheme(appearance)
                .background {
                    WindowChromeApplicator(color: nil)
                }
        }
    }
}

/// Paints the AppKit window so the title bar matches a named theme.
private struct WindowChromeApplicator: NSViewRepresentable {
    var color: NSColor?

    func makeNSView(context: Context) -> WindowChromeView {
        WindowChromeView()
    }

    func updateNSView(_ view: WindowChromeView, context: Context) {
        view.apply(color)
    }
}

private final class WindowChromeView: NSView {
    private var color: NSColor?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply(color)
    }

    func apply(_ color: NSColor?) {
        self.color = color
        guard let window else { return }
        if let color {
            window.backgroundColor = color
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isOpaque = true
        } else {
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .automatic
            window.isOpaque = true
        }
    }
}

extension View {
    func appThemeChrome(appearance: ColorScheme? = nil) -> some View {
        modifier(ThemedSceneModifier(appearance: appearance))
    }

    func appThemeSidebar() -> some View {
        modifier(ThemedSidebarBackground())
    }

    func appThemeSurface() -> some View {
        modifier(ThemedSurfaceBackground())
    }

    func appThemePresentationBackground() -> some View {
        modifier(ThemedPresentationBackground())
    }

    func appThemeBarBackground() -> some View {
        modifier(ThemedBarBackground())
    }
}

private struct ThemedSidebarBackground: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if let sidebar = theme.chrome?.sidebar {
            content
                .scrollContentBackground(.hidden)
                .background(sidebar.ignoresSafeArea())
        } else {
            content
        }
    }
}

private struct ThemedSurfaceBackground: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if let surface = theme.chrome?.surface {
            content.background(surface)
        } else {
            content
        }
    }
}

private struct ThemedPresentationBackground: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if let chrome = theme.chrome {
            content
                .tint(chrome.accent)
                .preferredColorScheme(chrome.colorScheme)
                .presentationBackground(chrome.surface)
        } else {
            content
        }
    }
}

private struct ThemedBarBackground: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if let chrome = theme.chrome {
            content.background(chrome.window)
        } else {
            content.background(.bar)
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
