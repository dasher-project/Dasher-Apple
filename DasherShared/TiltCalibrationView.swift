import SwiftUI

#if canImport(UIKit)

/// Tilt calibration UI for iOS.
///
/// Guides the user through tilting their device to record the min/max
/// tilt range. The process:
/// 1. User taps "Start Calibrating"
/// 2. Tilts device to all extremes while the UI records min/max gravity values
/// 3. User taps "Done" to save
///
/// The calibration is persisted and loaded automatically on next session.
/// Default calibration assumes moderate vertical tilt (forward/back = Y,
/// left/right = X).
@available(iOS 17, *)
struct TiltCalibrationView: View {
    var tiltService: TiltInputService
    @Environment(\.dismiss) private var dismiss
    @State private var tick = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Tilt Calibration")
                .font(.title2.bold())

            if tiltService.isCalibrating {
                calibrationActiveView
            } else {
                calibrationIdleView
            }
        }
        .padding()
        .navigationTitle("Tilt Calibration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !tiltService.isActive {
                tiltService.startCalibrationMotionUpdates()
            }
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            if tiltService.isCalibrating {
                tiltService.updateCalibrationFromMotion()
                tick += 1
            }
        }
    }

    private var calibrationIdleView: some View {
        VStack(spacing: 16) {
            Text("Tilt your device through its full range of motion during calibration.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Hold the device upright, then tilt forward and back", systemImage: "arrow.up.and.down")
                Label("Tilt left and right through the full range", systemImage: "arrow.left.and.right")
                Label("Move slowly and smoothly through all positions", systemImage: "hand.draw")
            }
            .font(.subheadline)

            Button("Start Calibrating") {
                tiltService.startCalibration()
            }
            .buttonStyle(.borderedProminent)

            if tiltService.calibrationMaxY > tiltService.calibrationMinY {
                Divider()
                Text("Current Calibration")
                    .font(.headline)
                Text("Y: \(String(format: "%.3f", tiltService.calibrationMinY)) to \(String(format: "%.3f", tiltService.calibrationMaxY))")
                Text("X: \(String(format: "%.3f", tiltService.calibrationMinX)) to \(String(format: "%.3f", tiltService.calibrationMaxX))")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var calibrationActiveView: some View {
        VStack(spacing: 16) {
            Text("Tilt your device now...")
                .font(.title3)
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                HStack {
                    Text("Y range:")
                    Spacer()
                    Text("\(String(format: "%.3f", tiltService.calibrationMinY)) to \(String(format: "%.3f", tiltService.calibrationMaxY))")
                        .monospacedDigit()
                }
                HStack {
                    Text("X range:")
                    Spacer()
                    Text("\(String(format: "%.3f", tiltService.calibrationMinX)) to \(String(format: "%.3f", tiltService.calibrationMaxX))")
                        .monospacedDigit()
                }
            }
            .font(.body)
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))

            Button("Done") {
                tiltService.stopCalibration()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#endif
