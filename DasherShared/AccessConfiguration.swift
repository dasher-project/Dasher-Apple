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

    // MARK: - Auto-calibration override (DasherCore #64/#65)

    private static let autocalibrateOverrideKey = "autocalibrate_user_override"

    /// Explicit user choice for `BP_AUTOCALIBRATE`. `nil` (the default) =
    /// follow the access method (eye gaze on, everything else off). `true`/
    /// `false` = the user moved the Settings switch *against* the method
    /// default and that choice sticks across launches and method changes.
    public static var autocalibrateOverride: Bool? {
        get {
            SharedDefaults.fallback.object(forKey: autocalibrateOverrideKey) as? Bool
        }
        set {
            if let value = newValue {
                SharedDefaults.fallback.set(value, forKey: autocalibrateOverrideKey)
            } else {
                SharedDefaults.fallback.removeObject(forKey: autocalibrateOverrideKey)
            }
        }
    }

    /// Called from the Settings UI when the user flips the auto-calibration
    /// switch. Setting it back to the method default clears the override
    /// (behavior returns to "follow the access method"); setting it against
    /// the default records the explicit choice.
    public static func userToggledAutocalibrate(to value: Bool, method: AccessMethod) {
        autocalibrateOverride = (value == (method == .eyeGaze)) ? nil : value
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
        // "wobbly cursor" reports). An explicit user override from Settings
        // (autocalibrateOverride) always wins. v0.2.9 also makes the learned
        // offset session-scoped and ignores stale persisted offsets from older
        // builds, so upgraders need no manual settings wipe.
        bridge.setBoolParameter(key: bridge.findParameterKey("BP_AUTOCALIBRATE"),
                                value: Self.autocalibrateOverride ?? (method == .eyeGaze))

        if needsSwitchProfile, let profile = switchProfile {
            let buttonMap = profile.buttonMapString
            bridge.setStringParameter(key: bridge.findParameterKey("SP_BUTTON_MAPPINGS"), value: buttonMap)
            bridge.setLongParameter(key: bridge.findParameterKey("LP_BUTTON_SCAN_TIME"), value: UInt32(profile.scanRateMs))
        }
    }
}
