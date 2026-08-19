import SwiftUI
import HotKey
import WindowThingCore

struct SettingsView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            // Layouts are listed, applied and edited in the Show Layout surface —
            // no second place to manage them.

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(1)
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @State private var launchAtLogin = false
    @State private var showDockIcon = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Show in Dock", isOn: $showDockIcon)
            }

            Section("Activation Hotkey") {
                HStack {
                    Text("Current: \(activationHotKeyLabel)")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Edit in config file")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Configuration") {
                Button("Open Config File") {
                    let configPath = ConfigManager.shared.configFilePath
                    NSWorkspace.shared.open(configPath)
                }

                Button("Reload Configuration") {
                    ConfigManager.shared.loadConfig()
                    LayoutManager.shared.loadLayouts(from: ConfigManager.shared.config)
                }
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if AXIsProcessTrusted() {
                        Text("Granted")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant Access") {
                            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                            _ = AXIsProcessTrustedWithOptions(options)
                        }
                    }
                }
                Text("Required. WindowThing cannot move windows without it.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Screen Recording")
                    Spacer()
                    if CGPreflightScreenCaptureAccess() {
                        Text("Granted")
                            .foregroundColor(.green)
                    } else {
                        Button("Open Settings…", action: openScreenRecordingSettings)
                    }
                }
                Text("Optional, for live window previews. Without it WindowThing shows app icons instead.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Send the user to the Screen Recording pane.
    ///
    /// macOS shows the screen-recording prompt at most **once per app, ever**.
    /// After that first request, `CGRequestScreenCaptureAccess()` returns
    /// immediately without showing anything, so an app that only ever calls it
    /// leaves the user with no way back if that one prompt was missed or
    /// dismissed. Requesting first still covers the never-asked case; opening
    /// the pane covers every case after it.
    private func openScreenRecordingSettings() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Render the configured hotkey rather than a literal — the two drifted
    /// apart once the default changed.
    private var activationHotKeyLabel: String {
        let config = ConfigManager.shared.config.activationHotKey
        var label = ""
        for modifier in config.modifiers {
            switch modifier.lowercased() {
            case "control", "ctrl":      label += "⌃"
            case "option", "opt", "alt": label += "⌥"
            case "shift":                label += "⇧"
            case "command", "cmd":       label += "⌘"
            default:                     break
            }
        }
        label += Key(carbonKeyCode: config.keyCode).map(String.init(describing:)) ?? "?"
        return label
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.split.3x3")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("WindowThing")
                .font(.title)
                .fontWeight(.bold)

            // Read from the bundle so this can't drift from what was shipped.
            // Falls back for `swift run`, which has no Info.plist.
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .foregroundColor(.secondary)

            Text("A powerful window management app for macOS")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Text("Built with Swift and SwiftUI")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Configuration stored in YAML")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(40)
    }
}
