import SwiftUI

/// Settings form: General (launch at login), Charts (time window, per-chart
/// units), Ping (editable host list with validation).
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var speedTester: SpeedTester
    @State private var newHost = ""
    @State private var newLabel = ""
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
                if let detail = settings.launchAtLoginErrorDetail {
                    Text("\(L("Couldn't change Launch at Login")): \(detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(L("Requires the installed app bundle (see README)."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Picker(L("Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                Picker(L("Menu Bar Style"), selection: $settings.barMode) {
                    ForEach(BarMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Picker(L("Menu Bar Shows"), selection: $settings.barContent) {
                    ForEach(BarContent.allCases) { content in
                        Text(content.label).tag(content)
                    }
                }
                if settings.barContent == .capacity {
                    Text(L("Capacity values come from the periodic speed test."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
                ForEach($settings.pingHosts) { $host in
                    HStack(spacing: 8) {
                        TextField(L("Label"), text: $host.label)
                            .textFieldStyle(.plain)
                        Spacer()
                        Text(host.address)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button {
                            settings.pingHosts.removeAll { $0.id == host.id }
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
                    TextField(L("Label"), text: $newLabel)
                        .textFieldStyle(.roundedBorder)
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
        .onChange(of: settings.barContent) {
            // Capacity mode is only meaningful with fresh measurements:
            // ensure the auto test is on and produce a first value promptly.
            guard settings.barContent == .capacity else { return }
            if settings.speedTestInterval == .off {
                settings.speedTestInterval = .minutes30
                speedTester.applyAutoInterval(.minutes30)
            }
            // A persisted result can be days old (and from another network);
            // refresh unless it is younger than the auto-test interval.
            speedTester.refreshIfStale(maxAge: TimeInterval(settings.speedTestInterval.rawValue * 60))
        }
    }

    private func addHost() {
        let address = newHost.trimmingCharacters(in: .whitespaces)
        guard AppSettings.isValidHost(address) else {
            hostError = true
            return
        }
        hostError = false
        if !settings.pingHosts.contains(where: { $0.address == address }) {
            settings.pingHosts.append(
                PingHost(address: address, label: newLabel.trimmingCharacters(in: .whitespaces))
            )
        }
        newHost = ""
        newLabel = ""
    }
}
