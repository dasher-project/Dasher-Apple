import Foundation

struct AccessConfiguration: Codable, Equatable {
    var method: AccessMethod
    var selection: SelectionMethod
    var switchProfile: SwitchProfile?

    static let storageKey = "access_configuration"

    static var current: AccessConfiguration {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey),
                  let config = try? JSONDecoder().decode(AccessConfiguration.self, from: data) else {
                return defaultConfiguration
            }
            return config
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static var defaultConfiguration: AccessConfiguration {
        #if os(iOS)
        AccessConfiguration(method: .touch, selection: .continuous, switchProfile: nil)
        #elseif os(macOS)
        AccessConfiguration(method: .pointer, selection: .continuous, switchProfile: nil)
        #elseif os(visionOS)
        AccessConfiguration(method: .handTracking, selection: .continuous, switchProfile: nil)
        #else
        AccessConfiguration(method: .pointer, selection: .continuous, switchProfile: nil)
        #endif
    }

    var needsSwitchProfile: Bool {
        selection.isSwitchBased
    }

    func apply(to bridge: AccessSettingsBridge) {
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

enum ParameterKeys {
    static let spInputFilter = 101
    static let spInputDevice = 102
    static let spButtonMappings = 103
    static let bpStopOutside = 19
    static let bpAutocalibrate = 21
    static let lpButtonScanTime = 53
    static let lpMaxBitrate = 29
    static let bpAutoSpeedcontrol = 14
}
