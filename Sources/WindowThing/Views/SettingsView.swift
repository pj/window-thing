import SwiftUI
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

            LayoutsSettingsView()
                .tabItem {
                    Label("Layouts", systemImage: "rectangle.split.3x3")
                }
                .tag(1)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(2)
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
                    Text("Current: ⇧⌘Space")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Change...") {
                        // TODO: Implement hotkey recorder
                    }
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

            Section("Accessibility") {
                HStack {
                    Text("Accessibility Permission")
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
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Layouts Settings

struct LayoutsSettingsView: View {
    @State private var layouts: [WTLayout] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configured Layouts")
                .font(.headline)

            if layouts.isEmpty {
                Text("No layouts configured. Edit the config file to add layouts.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(layouts) { layout in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(layout.name)
                                .font(.body)
                            if let quickKey = layout.quickKey {
                                Text("Quick key: \(quickKey)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button("Apply") {
                            LayoutManager.shared.applyLayout(layout)
                        }
                    }
                }
            }

            HStack {
                Button("Edit Config") {
                    let configPath = ConfigManager.shared.configFilePath
                    NSWorkspace.shared.open(configPath)
                }
                Spacer()
                Button("Refresh") {
                    layouts = LayoutManager.shared.layouts
                }
            }
        }
        .padding()
        .onAppear {
            layouts = LayoutManager.shared.layouts
        }
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

            Text("Version 0.1.0")
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
