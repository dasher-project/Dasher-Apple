# Input System Design

Dasher's input system is a two-part architecture:

1. **Input Device** (`SP_INPUT_DEVICE`) — provides raw pointer coordinates to the engine.
2. **Input Filter** (`SP_INPUT_FILTER`) — interprets those coordinates into Dasher movement.

Any device can pair with any filter. The pairing happens at the engine level —
the active filter's `Timer()` reads coordinates from the active device each frame.

This design is shared across all Dasher frontends (Apple, Windows, GTK).
DasherCore is cross-platform and should not contain platform-specific input code.
Platform frontends register their own input devices.

## Architecture

### DasherCore (Cross-Platform Engine)

- `CDasherInput` (base class, `DasherInput.h`) — abstract. Subclasses provide coordinates.
  - `CScreenCoordInput` — provides screen-pixel coordinates.
  - `CDasherCoordInput` — provides Dasher-internal coordinates.
  - `CDasherVectorInput` — provides normalized [-1,1] vectors.
- `CInputFilter` (base class, `InputFilter.h`) — abstract. Subclasses interpret coordinates.
  - 15 built-in filters registered in `DasherInterfaceBase::CreateModules()`.
- `ModuleManager` — registry for devices and filters, looked up by name string.
- `SP_INPUT_DEVICE` / `SP_INPUT_FILTER` — string parameters storing the active module name.

### C API (DasherCore/src/dasher.h)

The C API provides a built-in `PointerInput` device that receives coordinates from:
- `dasher_mouse_move(ctx, x, y)` — sets pointer position (pixels)
- `dasher_mouse_down(ctx)` — signals press (sets BP_START_MOUSE, sends KeyDown)
- `dasher_mouse_up(ctx)` — signals release (sends KeyUp)
- `dasher_key_event(ctx, key, pressed)` — arbitrary key/switch events
  - key 0 = Start/Stop, 1-4 = Buttons, 100 = Primary, 101 = Secondary, 102 = Tertiary

Platform frontends feed these functions from their native input systems (touch, mouse,
hover, accelerometer, gamepad, etc.).

### Built-in Filters (from DasherInterfaceBase::CreateModules)

| Filter Name | Class | Description |
|---|---|---|
| Normal Control | CDefaultFilter | Standard continuous pointer control |
| Press Mode | CPressFilter | Hold to zoom, release to pause |
| Smoothing Mode | CSmoothingFilter | Smoothed pointer with less jitter |
| One Dimensional Mode | COneDimensionalFilter | Vertical-only control |
| Click Mode | CClickFilter | Click to select target zone |
| One Button Mode | COneButtonFilter | Single switch scanning |
| One Button Dynamic Mode | COneButtonDynamicFilter | Single switch with dynamic timing |
| Two Button Dynamic Mode | CTwoButtonDynamicFilter | Two switches (e.g. up/down) |
| Two Push Dynamic Mode | CTwoPushDynamicFilter | Two switches with push timing |
| Menu Mode | CButtonMode (scanning) | Scanning box selection |
| Direct Mode | CButtonMode (direct) | Direct box selection |
| Alternating Direct Mode | CAlternatingDirectMode | Alternating button direct selection |
| Compass Mode | CCompassMode | 4/8-direction compass selection |
| Stylus Control | CStylusFilter | Stylus/pen with hover pressure |

## Platform Presets

Rather than exposing raw device/filter names, frontends should present **presets** that
pair a user-friendly input method with the correct device + filter combination.
This is what Dasher v5's InputMethodSelector did.

### iOS Presets

| Preset | Input Source | Filter | Notes |
|---|---|---|---|
| Touch | Pointer (touch events) | Normal Control | Default |
| Eyegaze | Pointer (hover events / iPad Pro eye tracking) | Stylus Control or Normal Control | Uses UIHoverGestureRecognizer; iPad Pro has built-in eye tracking |
| Switch (1 switch) | Key events via iOS Switch Control | One Button Dynamic Mode | iOS Switch Control maps to key events |
| Switch (2 switches) | Key events via Bluetooth switches | Two Button Dynamic Mode | Two hardware or virtual switches |
| Keyboard | Hardware keyboard arrow keys | Two Button Dynamic Mode | Arrow keys as switch inputs |
| Scanning | Pointer (tap) | Menu Mode | Auto-scan, tap to select |
| Tilt | CoreMotion accelerometer (CMMotionManager) | One Dimensional Mode | Needs calibration UI; reuse v5 math |
| Two-finger | Multi-touch | Normal Control | Pinch distance = speed |

### macOS Presets

| Preset | Input Source | Filter | Notes |
|---|---|---|---|
| Mouse | Pointer (mouse/trackpad) | Normal Control | Default |
| Eyegaze | Pointer (eye tracker as mouse) | Stylus Control | Eye trackers typically present as mouse |
| Switch (keyboard) | Key events | One/Two Button Dynamic | Accessibility switches via keyboard |
| Joystick | GameController framework (GCController) | Normal Control | MFi/gamepad |

### visionOS Presets

| Preset | Input Source | Filter | Notes |
|---|---|---|---|
| Hand tracking | Pointer (pinch + hand position) | Normal Control | Default |
| Hand point + finger switches | ARKit HandTrackingProvider | One/Two Button Dynamic | One hand points, other hand's pinches are switches |
| Dwell | Pointer + dwell timer | Normal Control | Look at position, dwell to activate |

## visionOS: Hand Point + Finger Switches

Use one hand to point (position feeds `dasher_mouse_move()`),
and individual finger pinches on the other hand as switch events (`dasher_key_event()`).

- Pointer hand: ARKit `HandTrackingProvider` → project palm position to screen coords → `dasher_mouse_move()`
- Switch hand: detect thumb+finger pinches via `HandSkeleton` joint proximity → `dasher_key_event(key, pressed)`
  - Thumb + index = switch 1 (key 1)
  - Thumb + middle = switch 2 (key 2)
  - Thumb + ring = switch 3 (key 3)
  - Open hand = pause (key 0)
- Requires `com.apple.developer.arkit.hand-tracking` entitlement
- Add visual feedback (dot on canvas showing where user is pointing)

## Implementation Phases

### Phase 1: Presets UI (no new native input devices needed)
- Create `InputMethodPreset` struct in `DasherShared/InputMethodPreset.swift`
- Build `InputMethodSelectorView` (SwiftUI, shared across platforms)
- Wire preset selection → `SP_INPUT_DEVICE` + `SP_INPUT_FILTER` via bridge
- All presets use the existing `PointerInput` device + key events
- Touch, Eyegaze (hover), Switch, Keyboard, Scanning all work through existing C API

### Phase 2: Tilt Input (iOS)
- Create `TiltInputService` using `CMMotionManager`
- Feed accelerometer data to `dasher_mouse_move()`
- Add calibration UI (record neutral position, main axis, slow axis)
- Reuse median filter math from v5 `IPhoneInputs.mm`

### Phase 3: Advanced Inputs
- macOS: GameController joystick/gamepad via `GCController`
- visionOS: ARKit hand tracking + finger switches
- iOS: Two-finger multi-touch mode, GameController support and Facial tracking using native ARKit

## Cross-Platform Considerations

DasherCore is used by Dasher-Apple, Dasher-Windows, and Dasher-GTK (Linux).
The input device/filter architecture in DasherCore should NOT contain platform-specific code.
Platform frontends are responsible for:
- Registering their own `CDasherInput` subclasses (or using the C API's built-in `PointerInput`)
- Feeding native input events into the C API functions
- Providing platform-appropriate preset UIs

New input methods (future: brain-computer interfaces, breath sensors, EMG, etc.)
only need to feed `dasher_mouse_move()` and/or `dasher_key_event()` — no DasherCore changes required.

## Reference: Dasher v5 iPhone Implementation

| File | What it did |
|---|---|
| `../dasher/Src/iPhone/Classes/IPhoneInputs.h/.mm` | 4 input devices: Touch, Undoubled Touch, Tilt (UIAccelerometer), Two-finger |
| `../dasher/Src/iPhone/Classes/IPhoneFilters.h/.mm` | iPhone-specific filters: Touch Filter, Tilt Filter (1D + hold-to-go), Two-finger Filter |
| `../dasher/Src/iPhone/Classes/InputMethodSelector.mm` | Preset UI: 3 sections (Normal Steering, Box Modes, Dynamic Modes) with per-method settings |
| `../dasher/Src/iPhone/Classes/CalibrationController.mm/.h` | Tilt calibration UI |
| `../dasher/Src/Gtk2/tilt_input.h` | Linux tilt input (serial port accelerometer) |
| `../dasher/Src/Gtk2/joystick_input.h` | Linux joystick (3 variants: continuous, discrete zones, 1D) |
| `../dasher/Src/Win32/BTSocketInput.h/.cpp` | Windows Bluetooth socket input |
