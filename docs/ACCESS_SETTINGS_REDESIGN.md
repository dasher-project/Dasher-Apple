# Access Settings Redesign

## Problem

The current preset model conflates two orthogonal concerns:

1. **How you steer** (pointer input device: mouse, touch, eyegaze, tilt, joystick)
2. **How you select/confirm** (input filter: continuous tracking, click-to-zoom, dwell, button/switch, scanning)

These combine. E.g., an eyegaze user might steer with gaze but select via dwell, or via a physical switch. A tilt user steers by tilting but might select with a physical button or dwell.

## DasherCore Architecture

DasherCore already splits these:
- **`SP_INPUT_DEVICE`** (key 102) = the coordinate source. Currently "Pointer Input" for all Apple platforms via `dasher_mouse_move()`
- **`SP_INPUT_FILTER`** (key 101) = how coordinates + button events are interpreted

Some "devices" are really frontend services (tilt, eyegaze, joystick) that feed coordinates to the same `PointerInput` device. They're not separate DasherCore devices — they're *frontend input sources*.

## Design Decisions

- Method and Selection are **separate single-choice pickers** — not multi-select
- Invalid method+selection combos are **hidden** from the user
- **No "Simple" mode** — replace the flat preset list entirely with Method + Selection
- Switch configuration uses **key-capture per switch** ("Press key or switch now...")
- **Voice input** is not planned for now, can be added later since the architecture supports it
- Dwell is presented as a selection method for UX clarity (internally it's DefaultFilter + BP_STOP_OUTSIDE)

## Data Model

### AccessMethod (steering)

```swift
enum AccessMethod: String, CaseIterable, Identifiable {
    case pointer       // mouse/trackpad
    case touch         // direct touch
    case eyeGaze       // eye tracker camera
    case tilt          // CoreMotion accelerometer
    case joystick      // gamepad/GCController
    case handTracking  // visionOS ARKit hands
    case switchesOnly  // no continuous steering, buttons only
}
```

Each case has: `displayName`, `iconName` (SF Symbol), `subtitle`, `availablePlatforms`

### SelectionMethod (confirmation)

```swift
enum SelectionMethod: String, CaseIterable, Identifiable {
    case continuous    // Normal Control
    case pressToMove   // Press Mode
    case clickToZoom   // Click Mode
    case dwell         // Normal Control + BP_STOP_OUTSIDE
    case oneSwitch     // One Button Dynamic
    case twoSwitches   // Two Button Dynamic
    case twoPush       // Two Push Dynamic
    case scanning      // Menu Mode (auto-scan)
    case directBoxes   // Direct Mode
}
```

Each case has: `displayName`, `iconName`, `filterName` (maps to DasherCore SP_INPUT_FILTER), `validMethods`

### SwitchProfile

```swift
struct SwitchProfile: Codable {
    var switches: [SwitchSlot]  // up to 4
    var scanRate: Int           // LP_BUTTON_SCAN_TIME
}

struct SwitchSlot: Codable, Identifiable {
    let id: Int          // 1-4
    var label: String    // "Switch 1", "Switch 2" etc
    var keyCode: Int?    // captured key code, nil = unassigned
    var dasherButton: Int // Maps to Keys::VirtualKey (0-4)
}
```

### AccessConfiguration (persisted)

```swift
struct AccessConfiguration: Codable {
    var method: AccessMethod
    var selection: SelectionMethod
    var switchProfile: SwitchProfile?
}
```

## Compatibility Matrix

`SelectionMethod.validFor(method:)` determines which selection methods show:

| Method | Valid Selections |
|---|---|
| pointer | continuous, pressToMove, clickToZoom, dwell, oneSwitch, twoSwitches, twoPush, scanning, directBoxes |
| touch | continuous, pressToMove, clickToZoom, dwell, oneSwitch, twoSwitches, twoPush, scanning, directBoxes |
| eyeGaze | continuous, dwell, oneSwitch, twoSwitches, scanning, directBoxes |
| tilt | continuous, pressToMove, oneSwitch, twoSwitches, twoPush, scanning, directBoxes |
| joystick | continuous, pressToMove, clickToZoom, oneSwitch, twoSwitches, scanning, directBoxes |
| handTracking | continuous, dwell, oneSwitch, twoSwitches |
| switchesOnly | oneSwitch, twoSwitches, twoPush, scanning, directBoxes |

## DasherCore Filter Reference

| Filter Name | Class | Type |
|---|---|---|
| Normal Control | CDefaultFilter | Continuous steering |
| Press Mode | CPressFilter | Press-to-move |
| Smoothing Mode | CSmoothingFilter | Smoothed press-to-move |
| Stylus Control | CStylusFilter | Stylus with tap-to-zoom |
| One Dimensional Mode | COneDimensionalFilter | 1D (tilt) |
| Click Mode | CClickFilter | Discrete click-zoom |
| One Button Dynamic Mode | COneButtonDynamicFilter | Single switch |
| Two Button Dynamic Mode | CTwoButtonDynamicFilter | Two switches |
| Two Push Dynamic Mode | CTwoPushDynamicFilter | Single switch, timing-based |
| Menu Mode | CButtonMode (bMenu=true) | Auto-scan boxes |
| Direct Mode | CButtonMode (bMenu=false) | Direct box mapping |
| Static One Button Mode | COneButtonFilter | Scan line sweep |
| Alternating Direct Mode | CAlternatingDirectMode | Alternating box sizes |
| Compass Mode | CCompassMode | 4 directional boxes |

## DasherCore Key Parameters

- `SP_INPUT_FILTER` (key 101) — filter name string
- `SP_INPUT_DEVICE` (key 102) — device name string
- `SP_BUTTON_MAPPINGS` (key 103) — button mapping string
- `BP_STOP_OUTSIDE` — pause when pointer leaves canvas (for dwell)
- `BP_AUTOCALIBRATE` — auto-adjust offset from user's average position
- `BP_AUTO_SPEEDCONTROL` — auto-adjust speed
- `LP_BUTTON_SCAN_TIME` — auto-scan interval (ms), 0=off
- `LP_MAX_BITRATE` — max speed
- `LP_HOLD_TIME` — min hold time for long press (ms)
- `LP_MULTIPRESS_TIME` — multi-press detection window (ms)

## UI Design

### AccessSettingsView (replaces InputMethodSelectorView)

```
Access
├── Section: "Steering Method" — single-select list of AccessMethods (filtered by platform)
├── Section: "Selection Method" — single-select list of SelectionMethods (filtered by validMethods)
├── Section: "Switch Setup" — only visible when selection is switch-based
│   ├── Switch 1: "Press key or switch now..."
│   ├── Switch 2: "Press key or switch now..."
│   ├── Switch 3: (optional)
│   ├── Switch 4: (optional)
│   └── Scan rate slider (only for scanning mode)
└── Section: "Method Settings" — per-method advanced settings
    ├── Tilt: calibration link
    ├── Eye gaze: smoothing, dwell time
    └── Joystick: axis selection, dead zone
```

### SwitchCaptureView

- Shows "Press key or switch now..."
- Listens for key events
- Records the key code, stores it in the SwitchSlot
- Visual feedback: shows captured key name

## Files to Create

1. `DasherShared/AccessMethod.swift` — AccessMethod enum
2. `DasherShared/SelectionMethod.swift` — SelectionMethod enum with filter mapping + compatibility
3. `DasherShared/SwitchProfile.swift` — SwitchProfile + SwitchSlot
4. `DasherShared/AccessConfiguration.swift` — combined config + persistence
5. `DasherShared/AccessSettingsView.swift` — main access settings UI
6. `DasherShared/SwitchCaptureView.swift` — key capture UI

## Files to Delete

1. `DasherShared/InputMethodPreset.swift` — replaced by AccessMethod + SelectionMethod
2. `DasherShared/InputMethodSelectorView.swift` — replaced by AccessSettingsView

## Files to Modify

1. `DasherApp/Sources/DasherSettingsView.swift` — wire in AccessSettingsView
2. `DasherMac/Sources/DasherMacApp.swift` — wire in AccessSettingsView
3. `DasherVision/Sources/DasherVisionApp.swift` — wire in AccessSettingsView

## Input Source Services

Frontend services that feed `dasher_mouse_move()`:

| Service | Status |
|---|---|
| Pointer/Mouse/Trackpad | Already working (default) |
| Touch | Already working (default) |
| Tilt (CoreMotion) | Code exists in TiltInputService.swift, needs wiring |
| Eye Gaze | New — needs eye tracker framework integration |
| Joystick/Gamepad | New — needs GCController integration |
| Hand Tracking (visionOS) | New — needs ARKit HandTrackingProvider |

Each service is activated based on `AccessConfiguration.method`. Only one runs at a time.

## Execution Order

1. Create data models (AccessMethod, SelectionMethod, SwitchProfile, AccessConfiguration)
2. Build compatibility matrix in SelectionMethod
3. Build AccessSettingsView + SwitchCaptureView
4. Wire into all 3 platform settings
5. Delete old InputMethodPreset + InputMethodSelectorView
6. Wire tilt service activation based on config
7. Test on device
