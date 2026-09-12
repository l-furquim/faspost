<p align="center">
  <img src="docs/icon.png" width="128" alt="Fastpost">
</p>

<h1 align="center">Fastpost</h1>

<p align="center">A simple native macOS HTTP client.</p>

Build and send requests, inspect responses, and keep collections on disk — without Electron, a browser runtime, or a cloud account.

Fastpost is built with SwiftUI (and AppKit only where SwiftUI cannot do the job, such as the code editor). It feels like a Mac app because it is one: system controls, menus, Settings, sandboxing, and a UI that stays fast because request state never invalidates the sidebar.

Requires **macOS 26** or later.

## Why native

Postman and similar tools grew into large, web-shaped products. Fastpost stays small on purpose.

- **Simple** — requests, folders, environments, and a response pane. No workspace cloud, no team sync, no plugin marketplace.
- **Native** — a real Mac window, `NavigationSplitView`, the system Settings scene (⌘,), and keyboard shortcuts you can remap.
- **Pleasant** — Apple-like spacing and typography. The default theme uses system colors so Light and Dark just work. Named themes restyle the whole app.
- **Fast** — no Chromium shell. HTTP runs through `URLSession`. The outline does not refresh when a response arrives.

## Workspaces and collections

A workspace is a folder you pick with the system open panel. Fastpost stores:

- `workspace.json` — workspace metadata and the active environment
- a Postman Collection v2.1 file (`*.postman_collection.json`)
- optional Postman environments (`*.postman_environment.json`)

You can create a new workspace or open an existing folder. Access uses security-scoped bookmarks, so the app stays sandboxed and still reads and writes the files you chose.

Collections are folders and requests. Create, rename, delete, and drag to reorder or nest. New Request and New Folder live in the sidebar footer, context menus, and the File menu.

## Requests

Each request has a method (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS), a URL, query params, headers, auth, and a body.

**Auth** — none, Basic, Bearer, or API key (header or query). Secret fields stay hidden unless you reveal them; that preference is not persisted.

**Body** — none, JSON, or form URL encoded. The JSON editor is a real `NSTextView`: syntax highlighting, four-space tabs, selectable response text even when the editor is read-only.

**Variables** — `{{name}}` in URLs, headers, and bodies. Collection variables live in the collection file. Environments are separate Postman files; switch the active one from the toolbar. Environment values override collection variables. Tokens interpolate only when you Send — unresolved names stay as `{{name}}` and are never written back into the request.

**Send** — ⌘↩. Responses show status (RFC reason phrase, e.g. `200 OK`), timing, size, final URL after redirects, body, headers, and cookies. JSON is highlighted with the current theme. Transport failures are distinct from HTTP error statuses.

## Workflow

- **Command palette** (⌘K) — run commands or jump to a request without leaving the keyboard.
- **Duplicate** (⌘D) — clone a request with a new id, named `Name Copy`.
- **Copy / paste** — ⌘C / ⌘V on the sidebar copies the request, not the window. Editing a URL or body still copies text.
- **Copy as cURL** (⇧⌘C) — exports the *resolved* request (variables interpolated), ready for a terminal.
- **Shortcuts** — remap from Settings → Shortcuts. Conflicts clear the other command. System reserves such as ⌘C / ⌘V / ⌘Q stay reserved.

## Settings

Preferences live in **Fastpost → Settings…** (⌘,), not in the workspace.

- **Request** — timeout, max response size, HTTP version hint (Automatic or HTTP/3), automatic URL encoding, redirects (count, preserve method, Authorization across hosts, Referer), SSL verification, minimum TLS, in-memory cookie jar, `Cache-Control: no-cache`.
- **Certificates** — client TLS (mTLS) by host: PEM (CRT + KEY) or PKCS#12.
- **Editor** — font size and indent width.
- **Appearance** — System / Light / Dark, plus themes: Default (system chrome), One Dark, Dracula, Nord, Tokyo Night, Monokai, Catppuccin Mocha, Solarized Dark. Named themes paint the whole window.

Only options that `URLSession` can actually honor are exposed. No decorative toggles.

## Install

Apple Silicon, macOS 26+. First launch: right-click **Fastpost.app** and choose **Open**.

### Homebrew

```bash
brew tap l-furquim/faspost https://github.com/l-furquim/faspost
brew install --cask fastpost
```

### Disk image or installer

Download `Fastpost-<version>.dmg` or `Fastpost-<version>.pkg` from the [GitHub Releases](https://github.com/l-furquim/faspost/releases). The DMG is drag-and-drop into `/Applications`. The PKG opens in Installer.app.

## Requirements

- macOS 26+
- Xcode 26+ to build from source

Open `fastpost.xcodeproj` and run the **fastpost** scheme. The product is `Fastpost.app`. Bundle ID is `furqas.fastpost`.
