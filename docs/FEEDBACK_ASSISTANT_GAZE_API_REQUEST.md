# Feedback Assistant Request: Continuous Eye-Gaze Coordinate API for visionOS

**Feedback Type:** Enhancement / API Request
**Component:** visionOS SDK → Accessibility / ARKit / UIKit
**Severity:** High — blocks an entire category of accessibility apps

---

## Title

Request continuous eye-gaze coordinate API on visionOS for accessibility/AAC apps

## Problem

Dasher is an accessibility text-entry system originally developed at Cambridge University (David MacKay, 1997). It uses continuous pointer position to drive a zooming alphabetic interface — the user steers toward letters by moving a pointer (mouse, finger, or **eye gaze**). Dasher is a critical communication tool for people with motor impairments (ALS, cerebral palsy, spinal cord injury, locked-in syndrome).

Apple Vision Pro has the best built-in eye tracking of any consumer device. It should be the **ideal platform for eye-gaze AAC** — no external hardware, precise tracking, already calibrated per-user. But we **cannot access continuous gaze coordinates** through any public API. This blocks Dasher — and every other gaze-driven accessibility app — from serving its core user base on visionOS.

## What we've tried (all deliver zero events in a windowed app)

We have exhaustively tested every API that Apple's documentation suggests should provide gaze tracking on visionOS. In a standard windowed (non-immersive) app:

| API | Documentation says | Actual behaviour | Evidence |
|-----|-------------------|-----------------|----------|
| `UIHoverGestureRecognizer` | "On visionOS, detects when the user is looking at a view" | **Zero events delivered** to a `UIView` inside `UIViewRepresentable` | Console.app logs: 0 `began`/`changed`/`ended` callbacks across 2+ minutes of active gaze |
| `.onContinuousHover` (SwiftUI) | Continuous hover phase tracking | **Zero `.active` phases delivered** to the view | Same — no callback fires |
| `UIPointerInteraction` | Pointer/gaze region callbacks | **Zero `regionFor` callbacks** | Delegate methods never invoked |

The system **is** tracking gaze — we see `beginScrollingWithRegion` events in Console.app with the correct window rect — but the data is routed only to `UIScrollView` scroll handling, not exposed as usable coordinates.

The only input that works is **pinch-and-drag**, which follows the **hand position** (where the pinch is in 3D space), not where the eyes are looking. This is unsuitable for users who need eye-only control.

## What we need

Two API levels would unblock gaze-driven accessibility apps. Either one would be sufficient.

### Option A: High-level UIKit/SwiftUI API (preferred for accessibility apps)

A simple, view-scoped API that delivers continuous `(x, y)` gaze coordinates relative to a specific view — analogous to how `UIHoverGestureRecognizer` is documented but doesn't actually work:

```swift
// Proposed: UIEyeTrackingSession (UIKit)
class UIEyeTrackingSession {
    static var isAuthorized: Bool { get }
    static func requestAuthorization(completion: @escaping (Bool) -> Void)
    
    weak var delegate: UIEyeTrackingSessionDelegate?
    func attach(to view: UIView)
    func detach()
}

protocol UIEyeTrackingSessionDelegate: AnyObject {
    func eyeTracking(_ session: UIEyeTrackingSession,
                     didUpdateGazeAt point: CGPoint,    // view-local coordinates
                     timestamp: CFTimeInterval)
    func eyeTrackingDidLoseFocus(_ session: UIEyeTrackingSession)
}

// SwiftUI equivalent
struct EyeTrackingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onEyeTracking { phase in
            switch phase {
            case .focused(let point):  // continuous (x, y) in view space
            case .unfocused:           // gaze left the view
            }
        }
    }
}
```

**Key requirements for this API:**
- Must work in **windowed apps** (not require `ImmersiveSpace`). Accessibility apps are standard windows.
- Must deliver coordinates at **≥30 FPS** (Dasher zooms at 60 FPS; 30 is the minimum for usable steering).
- Must be **gated behind a consent prompt** (like microphone/camera) for privacy — users opt in per-app.
- Should respect **Dwell Control and Switch Control** system settings — if the user has Dwell Control enabled, gaze delivery should adapt.

### Option B: Low-level ARKit provider (for maximum flexibility)

An `EyeTrackingProvider` analogous to the existing `HandTrackingProvider`, delivering gaze ray data in world space:

```swift
// Proposed: AREyeTrackingProvider (ARKit)
class AREyeTrackingProvider: DataProvider {
    var anchorUpdates: AsyncStream<AREyeAnchor> { get }
    var isAuthorized: Bool { get }
}

struct AREyeAnchor {
    let origin: SimdFloat3       // gaze ray origin (world space)
    let direction: SimdFloat3    // gaze ray direction (normalized)
    let leftEye: SimdFloat3      // separate per-eye (optional)
    let rightEye: SimdFloat3
    let timestamp: CFTimeInterval
    let fixationPoint: SimdFloat3?  // computed 3D fixation (optional)
}
```

Apps would intersect the gaze ray with their window's plane using `WorldTrackingProvider` device anchors.

**Key requirements:**
- Gated behind an entitlement + user consent prompt.
- Should work in **both** windowed and immersive contexts.
- Per-eye data is optional — a single combined gaze ray is sufficient for AAC use cases.

## Why this matters

### Accessibility impact
- **Eye-gaze AAC is life-critical infrastructure.** For a person with ALS in late stages, eye-gaze communication is their only way to speak, write, and interact with technology.
- Current eye-gaze AAC requires **expensive external hardware** (Tobii, EyeX, $500–$2000+) mounted to a monitor. Vision Pro has this hardware **built in** but doesn't expose it to developers.
- Apple Vision Pro could be the most accessible communication device ever made — **if** the gaze API existed.

### Market signal
- Apple has invested heavily in accessibility on visionOS (Eye Tracking accessibility feature on iPhone/iPad in iOS 18, Dwell Control announced for visionOS 26).
- But these are **system-level features only** — they help users interact with existing UI via gaze. They don't help apps that **need gaze as a continuous data stream** (AAC, creative tools, hands-free interfaces).
- Opening a developer API would enable an entire category of visionOS apps that cannot exist today.

### Precedent
- **iOS/iPadOS** already has `ARFaceTrackingConfiguration(eyeTrackingEnabled: true)` — ARKit eye tracking via TrueDepth camera. Vision Pro has superior eye tracking hardware but exposes less.
- **iPadOS 18** has a system Eye Tracking accessibility feature. Extending this to a developer API would be consistent with Apple's accessibility direction.
- The **system** already uses gaze data internally for foveated streaming and UI focus — the infrastructure exists. It just needs a privacy-safe developer surface.

## What we're NOT asking for

- Raw eye images or biometric data — just the gaze ray or screen coordinates.
- Background tracking — this should only work when the app is foregrounded and the user has consented.
- Unfettered access — entitlement gating and a privacy prompt are expected and welcome.

## Reproduction

To verify that current APIs deliver zero gaze events:

1. Create a visionOS app with a `UIViewRepresentable` wrapping a `UIView`.
2. Add a `UIHoverGestureRecognizer` to the view.
3. Run on Vision Pro (simulator does not simulate gaze).
4. Look around the view for 30+ seconds.
5. Observe: zero `began`/`changed`/`ended` callbacks in Console.app.

Sample project: [Dasher for visionOS](https://github.com/dasher-project/dasher), `DasherVision` target.

## Related Apple resources

- "Create accessible spatial experiences" (WWDC23, Session 10034)
- "Explore spatial accessory input on visionOS" (WWDC25, Session 289)
- visionOS 26 Dwell Control announcement (Apple Accessibility Preview, May 2026)
- `UIHoverGestureRecognizer` documentation (states it tracks gaze on visionOS but does not deliver events in windowed apps)

## Summary

Vision Pro has the hardware to be the world's best eye-gaze accessibility platform. A continuous gaze coordinate API — either high-level UIKit or low-level ARKit — would unlock AAC apps like Dasher, creative eye-gaze tools, and hands-free interfaces that cannot exist on visionOS today. We request either:

1. **Fix `UIHoverGestureRecognizer`** to actually deliver continuous gaze events in windowed apps (as documented), OR
2. **Add a new `UIEyeTrackingSession` / `.onEyeTracking` API** with consent gating, OR
3. **Add an `AREyeTrackingProvider`** to ARKit with an entitlement.

Any one of these would unblock Dasher and the broader gaze-driven accessibility ecosystem on visionOS.
