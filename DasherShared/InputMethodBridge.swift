import SwiftUI

protocol AccessSettingsBridge: AnyObject {
    func getStringParameter(key: Int) -> String
    func setStringParameter(key: Int, value: String)
    func getBoolParameter(key: Int) -> Bool
    func setBoolParameter(key: Int, value: Bool)
    func getLongParameter(key: Int) -> Int
    func setLongParameter(key: Int, value: Int)
    func mouseMove(x: Float, y: Float)
}

extension AccessSettingsBridge {
    func setTiltPosition(x: Float, y: Float) {
        mouseMove(x: x, y: y)
    }
}

extension AccessSettingsBridge {
    func setLongParameter(key: Int, value: UInt32) {
        setLongParameter(key: key, value: Int(value))
    }
}

typealias InputMethodBridge = AccessSettingsBridge
