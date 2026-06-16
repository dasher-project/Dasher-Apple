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
            bridge.setBoolParameter(key: bridge.findParameterKey("BP_AUTOCALIBRATE"), value: true)
        } else {
            bridge.setBoolParameter(key: bridge.findParameterKey("BP_STOP_OUTSIDE"), value: false)
        }

        if needsSwitchProfile, let profile = switchProfile {
            let buttonMap = profile.buttonMapString
            bridge.setStringParameter(key: bridge.findParameterKey("SP_BUTTON_MAPPINGS"), value: buttonMap)
            bridge.setLongParameter(key: bridge.findParameterKey("LP_BUTTON_SCAN_TIME"), value: UInt32(profile.scanRateMs))
        }
    }
}
