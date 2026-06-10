#if canImport(UIKit)

import Foundation
import CoreMotion
import UIKit

/// Provides tilt/accelerometer-based pointer control using CoreMotion.
///
/// Replaces the v5 CIPhoneTiltInput which used the deprecated UIAccelerometer.
/// The math is the same: project the gravity vector onto calibrated axes,
/// then apply a running median filter to smooth jitter.
///
/// ## How it works
/// 1. CMMotionManager provides device gravity (acceleration minus user accel)
/// 2. The gravity vector is projected onto two calibrated axes:
///    - **main axis**: maps tilt range to Y position (0 = top, 1 = bottom)
///    - **slow axis**: maps tilt range to X position (0 = left, 1 = right)
/// 3. A running median filter (window size 20) smooths the raw values
/// 4. The smoothed (x, y) is fed to the bridge as screen coordinates
///
/// ## Calibration
/// Two calibration modes, matching v5:
/// - **Vertical**: user tilts phone forward/back for Y, left/right for X.
///   Records minY/maxY and minX/maxX from live accelerometer data.
/// - **Custom**: user sets min vector, max vector, and slow axis vector.
///   For advanced users with non-standard mounting positions.
///
/// Calibration is persisted to UserDefaults and loaded on next session.
@MainActor
@Observable
final class TiltInputService {
    var isActive = false
    var isCalibrating = false
    var calibrationMode: TiltCalibrationMode = .vertical

    /// Live accelerometer values for calibration UI
    var currentGravity: (x: Double, y: Double, z: Double) = (0, 0, 0)
    var calibrationMinY: Double = 1.0
    var calibrationMaxY: Double = -1.0
    var calibrationMinX: Double = 1.0
    var calibrationMaxX: Double = -1.0

    private var motionManager: CMMotionManager?
    private var medianFilter = MedianFilter(windowSize: 20)

    /// The bridge to feed coordinates to. Set when tilt input activates.
    weak var bridge: InputMethodBridge?

    /// Screen dimensions for coordinate mapping. Updated by the canvas.
    var screenWidth: Int = 1
    var screenHeight: Int = 1

    // MARK: - Tilt Axes (from calibration)

    /// Main axis direction (normalized). Default: (0, 1, 0) = vertical.
    private var mainAxis: Vec3 = Vec3(x: 0, y: 1, z: 0)
    /// Offset for main axis projection (dot product at zero position).
    private var mainOffset: Double = 0
    /// Slow axis direction (normalized). Default: (1, 0, 0) = horizontal.
    private var slowAxis: Vec3 = Vec3(x: 1, y: 0, z: 0)
    /// Offset for slow axis projection.
    private var slowOffset: Double = 0

    // MARK: - Lifecycle

    func activate(bridge: InputMethodBridge) {
        self.bridge = bridge
        loadCalibration()
        motionManager = CMMotionManager()
        guard let motionManager, motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 100.0 // 100Hz
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)

        isActive = true
        medianFilter.reset()

        // Feed motion data on main thread via Timer
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

    func startCalibrationMotionUpdates() {
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

    func deactivate() {
        isActive = false
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
        medianFilter.reset()
    }

    // MARK: - Motion Processing

    private func processMotion() {
        guard let data = motionManager?.deviceMotion else { return }
        let gravity = data.gravity
        currentGravity = (gravity.x, gravity.y, gravity.z)

        if isCalibrating { return }

        let inVec = Vec3(x: gravity.x, y: gravity.y, z: gravity.z)

        // Project gravity onto main axis → Y position
        var y = dot(mainAxis, inVec) - mainOffset
        y = clamp(y, 0, 1)

        // Project gravity onto slow axis → X position
        var x = dot(slowAxis, inVec) - slowOffset
        x = clamp(x, 0, 1)

        // Map to screen coordinates
        let screenX = Int(x * Double(screenWidth))
        let screenY = Int(y * Double(screenHeight))

        // Apply median filter
        let filtered = medianFilter.push(x: screenX, y: screenY)

        // Feed to Dasher engine
        bridge?.setTiltPosition(x: Float(filtered.x), y: Float(filtered.y))
    }

    // MARK: - Calibration

    func startCalibration() {
        isCalibrating = true
        calibrationMinY = 1.0
        calibrationMaxY = -1.0
        calibrationMinX = 1.0
        calibrationMaxX = -1.0
    }

    func stopCalibration() {
        isCalibrating = false
        if calibrationMaxY > calibrationMinY {
            applyVerticalCalibration(
                minY: calibrationMinY, maxY: calibrationMaxY,
                minX: calibrationMinX, maxX: calibrationMaxX
            )
            saveCalibration()
        }
    }

    /// Update calibration range from live accelerometer data.
    /// Called from the motion timer during calibration.
    func updateCalibrationFromMotion() {
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

    // MARK: - Persistence

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
            // Default calibration: moderate tilt range
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

// MARK: - Supporting Types

enum TiltCalibrationMode {
    case vertical
    case custom
}

/// 3D vector for tilt axis math. Replaces v5's Vec3 C struct.
struct Vec3 {
    let x, y, z: Double

    static func - (lhs: Vec3, rhs: Vec3) -> Vec3 {
        Vec3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }
}

private func dot(_ a: Vec3, _ b: Vec3) -> Double {
    a.x * b.x + a.y * b.y + a.z * b.z
}

private func clamp(_ value: Double, _ min: Double, _ max: Double) -> Double {
    Swift.max(min, Swift.min(max, value))
}

/// Running median filter with configurable window size.
/// Replaces v5's SBTree-based median filter with a simpler sorted-array approach.
/// Keeps the last N samples and returns the median of each axis.
struct MedianFilter {
    let windowSize: Int
    private var xBuffer: [Int] = []
    private var yBuffer: [Int] = []

    init(windowSize: Int = 20) {
        self.windowSize = windowSize
    }

    mutating func reset() {
        xBuffer.removeAll()
        yBuffer.removeAll()
    }

    mutating func push(x: Int, y: Int) -> (x: Int, y: Int) {
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
