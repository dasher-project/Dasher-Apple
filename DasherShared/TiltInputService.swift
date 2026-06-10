#if canImport(UIKit)

import Foundation
import CoreMotion
import UIKit

@MainActor
@Observable
public final class TiltInputService {
    public var isActive = false
    public var isCalibrating = false
    public var calibrationMode: TiltCalibrationMode = .vertical

    public var currentGravity: (x: Double, y: Double, z: Double) = (0, 0, 0)
    public var calibrationMinY: Double = 1.0
    public var calibrationMaxY: Double = -1.0
    public var calibrationMinX: Double = 1.0
    public var calibrationMaxX: Double = -1.0

    private var motionManager: CMMotionManager?
    private var medianFilter = MedianFilter(windowSize: 20)

    public weak var bridge: InputMethodBridge?

    public var screenWidth: Int = 1
    public var screenHeight: Int = 1

    private var mainAxis: Vec3 = Vec3(x: 0, y: 1, z: 0)
    private var mainOffset: Double = 0
    private var slowAxis: Vec3 = Vec3(x: 1, y: 0, z: 0)
    private var slowOffset: Double = 0

    public init() {}

    public func activate(bridge: InputMethodBridge) {
        self.bridge = bridge
        loadCalibration()
        motionManager = CMMotionManager()
        guard let motionManager, motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)

        isActive = true
        medianFilter.reset()

        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else {
                    timer.invalidate()
                    return
                }
                self.processMotion()
            }
        }
    }

    public func startCalibrationMotionUpdates() {
        if motionManager == nil {
            motionManager = CMMotionManager()
        }
        guard let motionManager, motionManager.isDeviceMotionAvailable else { return }
        if !motionManager.isDeviceMotionActive {
            motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        }
        isActive = true
    }

    public func deactivate() {
        isActive = false
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
        medianFilter.reset()
    }

    private func processMotion() {
        guard let data = motionManager?.deviceMotion else { return }
        let gravity = data.gravity
        currentGravity = (gravity.x, gravity.y, gravity.z)

        if isCalibrating { return }

        let inVec = Vec3(x: gravity.x, y: gravity.y, z: gravity.z)

        var y = dot(mainAxis, inVec) - mainOffset
        y = clamp(y, 0, 1)

        var x = dot(slowAxis, inVec) - slowOffset
        x = clamp(x, 0, 1)

        let screenX = Int(x * Double(screenWidth))
        let screenY = Int(y * Double(screenHeight))

        let filtered = medianFilter.push(x: screenX, y: screenY)

        bridge?.setTiltPosition(x: Float(filtered.x), y: Float(filtered.y))
    }

    public func startCalibration() {
        isCalibrating = true
        calibrationMinY = 1.0
        calibrationMaxY = -1.0
        calibrationMinX = 1.0
        calibrationMaxX = -1.0
    }

    public func stopCalibration() {
        isCalibrating = false
        if calibrationMaxY > calibrationMinY {
            applyVerticalCalibration(
                minY: calibrationMinY, maxY: calibrationMaxY,
                minX: calibrationMinX, maxX: calibrationMaxX
            )
            saveCalibration()
        }
    }

    public func updateCalibrationFromMotion() {
        guard isCalibrating else { return }
        if let data = motionManager?.deviceMotion {
            currentGravity = (data.gravity.x, data.gravity.y, data.gravity.z)
        }
        let (x, y, _) = currentGravity
        calibrationMinY = min(calibrationMinY, y)
        calibrationMaxY = max(calibrationMaxY, y)
        calibrationMinX = min(calibrationMinX, x)
        calibrationMaxX = max(calibrationMaxX, x)
    }

    private func applyVerticalCalibration(minY: Double, maxY: Double, minX: Double, maxX: Double) {
        let yRange = maxY - minY
        let xRange = maxX - minX
        guard yRange > 0.01, xRange > 0.01 else { return }

        mainAxis = Vec3(x: 0, y: 1.0 / yRange, z: 0)
        mainOffset = minY / yRange
        slowAxis = Vec3(x: 1.0 / xRange, y: 0, z: 0)
        slowOffset = minX / xRange
    }

    private static let calibrationKey = "DasherTiltCalibration"

    private struct TiltCalibrationData: Codable {
        let minY, maxY, minX, maxX: Double
    }

    private func saveCalibration() {
        let data = TiltCalibrationData(
            minY: calibrationMinY, maxY: calibrationMaxY,
            minX: calibrationMinX, maxX: calibrationMaxX
        )
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: Self.calibrationKey)
        }
    }

    private func loadCalibration() {
        guard let data = UserDefaults.standard.data(forKey: Self.calibrationKey),
              let decoded = try? JSONDecoder().decode(TiltCalibrationData.self, from: data) else {
            applyVerticalCalibration(minY: -0.1, maxY: -0.9, minX: -0.4, maxX: 0.4)
            return
        }
        calibrationMinY = decoded.minY
        calibrationMaxY = decoded.maxY
        calibrationMinX = decoded.minX
        calibrationMaxX = decoded.maxX
        applyVerticalCalibration(
            minY: decoded.minY, maxY: decoded.maxY,
            minX: decoded.minX, maxX: decoded.maxX
        )
    }
}

#endif

public enum TiltCalibrationMode {
    case vertical
    case custom
}

public struct Vec3 {
    public let x, y, z: Double

    public static func - (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }
}

private func dot(_ a: Vec3, _ b: Vec3) -> Double {
    a.x * b.x + a.y * b.y + a.z * b.z
}

private func clamp(_ value: Double, _ min: Double, _ max: Double) -> Double {
    Swift.max(min, Swift.min(max, value))
}

public struct MedianFilter {
    public let windowSize: Int
    private var xBuffer: [Int] = []
    private var yBuffer: [Int] = []

    public init(windowSize: Int = 20) {
        self.windowSize = windowSize
    }

    public mutating func reset() {
        xBuffer.removeAll()
        yBuffer.removeAll()
    }

    public mutating func push(x: Int, y: Int) -> (x: Int, y: Int) {
        xBuffer.append(x)
        yBuffer.append(y)
        if xBuffer.count > windowSize {
            xBuffer.removeFirst()
            yBuffer.removeFirst()
        }
        let sortedX = xBuffer.sorted()
        let sortedY = yBuffer.sorted()
        let mid = sortedX.count / 2
        return (sortedX[mid], sortedY[mid])
    }
}
