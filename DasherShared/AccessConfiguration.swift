import Foundation

public struct AccessConfiguration: Codable, Equatable {
    public var method: AccessMethod
    public var selection: SelectionMethod
    public var switchProfile: SwitchProfile?

    public static let storageKey = "access_configuration"

    public static var current: AccessConfiguration {
        get {
            guard let data = SharedDefaults.fallback.data(forKey: storageKey),
                   let config = try? JSONDecoder().decode(AccessConfiguration.self, from: data) else {
                return defaultConfiguration
            }
            return config
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            SharedDefaults.fallback.set(data, forKey: storageKey)
        }
    }

    public static var defaultConfiguration: AccessConfiguration {
        #if os(iOS)
        AccessConfiguration(method: .touch, selection: .continuous, switchProfile: nil)
        #elseif os(macOS)
        AccessConfiguration(method: .pointer, selection: .continuous, switchProfile: nil)
        #elseif os(visionOS)
        AccessConfiguration(method: .eyeGaze, selection: .continuous, switchProfile: nil)
        #else
        AccessConfiguration(method: .pointer, selection: .continuous, switchProfile: nil)
        #endif
    }

    public var needsSwitchProfile: Bool {
        selection.isSwitchBased
    }

    public func apply(to bridge: AccessSettingsBridge) {
        bridge.setStringParameter(key: bridge.findParameterKey("SP_INPUT_FILTER"), value: selection.filterName)

        if selection == .dwell {
            bridge.setBoolParameter(key: bridge.findParameterKey("BP_STOP_OUTSIDE"), value: true)
        } else {
            bridge.setBoolParameter(key: bridge.findParameterKey("BP_STOP_OUTSIDE"), value: false)
        }

        // Auto-calibration follows the access method (Dasher-Windows #41 parity,
        // needs DasherCore >= v0.2.9): on for eye gaze — its original purpose,
        // Dasher's 2004 eye-tracker Y-error correction — and explicitly off for
        // pointer/touch/etc. For a pointer user deliberately steering off-centre
        // it drifted the steering offset every sentence (the restart-drift and
        // "wobbly cursor" reports). v0.2.9 also makes the learned offset
        // session-scoped and ignores stale persisted offsets from older builds,
        // so upgraders need no manual settings wipe.
        bridge.setBoolParameter(key: bridge.findParameterKey("BP_AUTOCALIBRATE"), value: method == .eyeGaze)

        if needsSwitchProfile, let profile = switchProfile {
            let buttonMap = profile.buttonMapString
            bridge.setStringParameter(key: bridge.findParameterKey("SP_BUTTON_MAPPINGS"), value: buttonMap)
            bridge.setLongParameter(key: bridge.findParameterKey("LP_BUTTON_SCAN_TIME"), value: UInt32(profile.scanRateMs))
        }
    }
}
