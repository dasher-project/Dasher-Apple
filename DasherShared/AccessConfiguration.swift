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
        bridge.setStringParameter(key: ParameterKeys.spInputFilter, value: selection.filterName)

        if selection == .dwell {
            bridge.setBoolParameter(key: ParameterKeys.bpStopOutside, value: true)
            bridge.setBoolParameter(key: ParameterKeys.bpAutocalibrate, value: true)
        } else {
            bridge.setBoolParameter(key: ParameterKeys.bpStopOutside, value: false)
        }

        if needsSwitchProfile, let profile = switchProfile {
            let buttonMap = profile.buttonMapString
            bridge.setStringParameter(key: ParameterKeys.spButtonMappings, value: buttonMap)
            bridge.setLongParameter(key: ParameterKeys.lpButtonScanTime, value: UInt32(profile.scanRateMs))
        }
    }
}

public enum ParameterKeys {
    public static let spInputFilter = 101
    public static let spInputDevice = 102
    public static let spButtonMappings = 103
    public static let bpStopOutside = 19
    public static let bpAutocalibrate = 21
    public static let lpButtonScanTime = 53
    public static let lpMaxBitrate = 29
    public static let bpAutoSpeedcontrol = 14
}
