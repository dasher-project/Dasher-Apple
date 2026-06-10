import SwiftUI

struct AccessSettingsView: View {
    let bridge: AccessSettingsBridge
    var onMethodChanged: ((AccessMethod) -> Void)?
    #if canImport(UIKit)
    var tiltService: TiltInputService?
    #endif

    @State private var config: AccessConfiguration = .current
    @State private var showTiltCalibration = false

    var body: some View {
        let validSelections = SelectionMethod.validFor(method: config.method)

        List {
            steeringSection
            selectionSection(validSelections)
            if config.needsSwitchProfile {
                switchSetupSection
            }
            methodSpecificSection
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Access")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            var saved = AccessConfiguration.current
            let validSelections = SelectionMethod.validFor(method: saved.method)
            if !validSelections.contains(saved.selection) {
                saved.selection = validSelections.first ?? .continuous
            }
            config = saved
        }
    }

    private func applyNow() {
        config.apply(to: bridge)
        AccessConfiguration.current = config
        onMethodChanged?(config.method)
    }

    private var steeringSection: some View {
        Section {
            ForEach(AccessMethod.allCases.filter(\.isAvailable)) { method in
                methodRow(method)
            }
        } header: {
            Label("Steering Method", systemImage: "cursorarrow.motionlines")
        }
    }

    private func selectionSection(_ validSelections: [SelectionMethod]) -> some View {
        Section {
            ForEach(validSelections) { method in
                selectionRow(method)
            }
        } header: {
            Label("Selection Method", systemImage: "hand.tap")
        }
    }

    private var switchSetupSection: some View {
        let profile = Binding<SwitchProfile>(
            get: { config.switchProfile ?? SwitchProfile() },
            set: { config.switchProfile = $0 }
        )
        return Section {
            ForEach(profile.switches.indices, id: \.self) { index in
                let slot = profile.wrappedValue.switches[index]
                let requiredIndex = slot.id - 1
                let isRequired = requiredIndex < config.selection.requiredSwitchCount
                if isRequired || slot.isAssigned {
                    SwitchCaptureRow(slot: Binding(
                        get: { profile.wrappedValue.switches[index] },
                        set: { profile.wrappedValue.switches[index] = $0 }
                    ), bridge: bridge)
                }
            }

            if config.selection == .scanning {
                VStack(alignment: .leading) {
                    Text("Scan Speed")
                    HStack {
                        Text("Slow")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(
                            get: { Double(profile.wrappedValue.scanRateMs) },
                            set: { profile.wrappedValue.scanRateMs = Int($0) }
                        ), in: 100...2000, step: 50)
                        Text("Fast")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(profile.wrappedValue.scanRateMs) ms per step")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Label("Switch Setup", systemImage: "switch.2")
        }
    }

    private var methodSpecificSection: some View {
        Group {
            switch config.method {
            case .tilt:
                tiltSection
            default:
                EmptyView()
            }
        }
    }

    private var tiltSection: some View {
        Section {
            #if canImport(UIKit)
            if let tiltService {
                NavigationLink {
                    TiltCalibrationView(tiltService: tiltService)
                } label: {
                    Label("Calibrate Tilt", systemImage: "sensor.tag.radiowaves.forward")
                }
            } else {
                Text("Enable tilt input first to access calibration.")
                    .foregroundStyle(.secondary)
            }
            #endif
        } header: {
            Label("Tilt Settings", systemImage: "arrow.up.left.and.arrow.down.right")
        }
    }

    private func methodRow(_ method: AccessMethod) -> some View {
        Button {
            var newConfig = config
            newConfig.method = method
            let validSelections = SelectionMethod.validFor(method: method)
            if !validSelections.contains(config.selection) {
                newConfig.selection = validSelections.first ?? .continuous
            }
            if !newConfig.needsSwitchProfile {
                newConfig.switchProfile = nil
            } else if newConfig.switchProfile == nil {
                newConfig.switchProfile = SwitchProfile()
            }
            config = newConfig
            applyNow()
        } label: {
            HStack {
                Image(systemName: method.iconName)
                    .frame(width: 28)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(method.displayName)
                        .font(.body)
                    Text(method.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if config.method == method {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func selectionRow(_ method: SelectionMethod) -> some View {
        Button {
            var newConfig = config
            newConfig.selection = method
            if newConfig.needsSwitchProfile && newConfig.switchProfile == nil {
                newConfig.switchProfile = SwitchProfile()
            } else if !newConfig.needsSwitchProfile {
                newConfig.switchProfile = nil
            }
            config = newConfig
            applyNow()
        } label: {
            HStack {
                Image(systemName: method.iconName)
                    .frame(width: 28)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(method.displayName)
                        .font(.body)
                    Text(method.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if config.selection == method {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
