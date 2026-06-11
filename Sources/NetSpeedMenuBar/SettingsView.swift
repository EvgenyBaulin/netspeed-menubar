import SwiftUI

/// Settings form: General (launch at login), Charts (time window, per-chart
/// units), Ping (editable host list with validation).
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var newHost = ""
    @State private var hostError = false

    var body: some View {
        Form {
            Section(L("General")) {
                Toggle(
                    L("Launch at Login"),
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    )
                )
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(L("Requires the installed app bundle (see README)."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Picker(L("Menu Bar Style"), selection: $settings.barMode) {
                    ForEach(BarMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L("Charts")) {
                Picker(L("Time Window"), selection: $settings.chartWindow) {
                    ForEach(ChartWindow.allCases) { window in
                        Text(window.label).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                Picker(L("Download Unit"), selection: $settings.downloadUnit) {
                    ForEach(SpeedUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                Picker(L("Upload Unit"), selection: $settings.uploadUnit) {
                    ForEach(SpeedUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
            }

            Section(L("Ping Hosts")) {
                ForEach(settings.pingHosts, id: \.self) { host in
                    HStack {
                        Text(host)
                            .monospacedDigit()
                        Spacer()
                        Button {
                            settings.pingHosts.removeAll { $0 == host }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L("Remove"))
                        .accessibilityLabel(L("Remove"))
                        .disabled(settings.pingHosts.count == 1)
                    }
                }
                HStack {
                    TextField(L("IP or hostname"), text: $newHost)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addHost)
                    Button(L("Add"), action: addHost)
                        .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if hostError {
                    Text(L("Invalid host name"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { settings.refreshLaunchAtLogin() }
    }

    private func addHost() {
        let host = newHost.trimmingCharacters(in: .whitespaces)
        guard AppSettings.isValidHost(host) else {
            hostError = true
            return
        }
        hostError = false
        if !settings.pingHosts.contains(host) {
            settings.pingHosts.append(host)
        }
        newHost = ""
    }
}
