import SwiftUI

enum SettingsTab: CaseIterable, Identifiable, Hashable {
    case peripherals
    case peers
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .peripherals: "Peripherals"
        case .peers: "Peers"
        case .general: "General"
        }
    }

    var systemImage: String {
        switch self {
        case .peripherals: "keyboard"
        case .peers: "network"
        case .general: "gear"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var deviceStore: BluetoothDeviceStore
    @ObservedObject var serviceBrowser: ServiceBrowser
    let connectionManager: ConnectionManager

    @State private var selectedTab: SettingsTab? = .peripherals

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
        } detail: {
            switch selectedTab ?? .peripherals {
            case .peripherals:
                PeripheralSettingsView(deviceStore: deviceStore)
            case .peers:
                PeerSettingsView(
                    serviceBrowser: serviceBrowser,
                    connectionManager: connectionManager
                )
            case .general:
                GeneralSettingsView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
        }
        .padding()
    }
}
