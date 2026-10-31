import Foundation

/// RFC 0001 2026-10-28 amendment: UI-interaction telemetry. Two events, both
/// opt-in gated by AnalyticsService.capture's no-op-before-consent, both in
/// the published schema:
///
/// - `ui_action` — a main-UI control was activated (fixed action vocabulary)
/// - `setting_changed` — a settings change was committed at its widget site
///   (never for programmatic engine changes). String settings record the
///   change but never the free-text value.
///
/// Mirrors Dasher-Android's UiTelemetry (implemented first, #79). Pure
/// formatting helpers over AnalyticsService — no state.
public enum UITelemetry {

    /// A main-UI control was activated. `surface` is one of `main_toolbar`,
    /// `status_bar`, `ime_toolbar`, `ime_topbar`; `action` uses the fixed
    /// vocabulary (`new`, `open`, `save`, `share`, `pause_play`, `game_mode`,
    /// `settings`, `copy`, `layout`, `speed_up`, `speed_down`, ...);
    /// `state` is present only for toggles (`on`/`off`, `paused`/`playing`).
    public static func action(_ surface: String, _ action: String, state: String? = nil) {
        var properties: [String: Any] = [
            "surface": surface,
            "action": action,
        ]
        if let state {
            properties["state"] = state
        }
        AnalyticsService.shared.capture("ui_action", properties: properties)
    }

    /// Bool setting committed by the user.
    public static func setting(_ id: String, _ value: Bool, surface: String) {
        AnalyticsService.shared.capture("setting_changed", properties: [
            "setting_id": id,
            "value_type": "bool",
            "value": value,
            "surface": surface,
        ])
    }

    /// Numeric setting committed by the user (speeds, sizes — not PII).
    public static func setting(_ id: String, _ value: Int, surface: String) {
        AnalyticsService.shared.capture("setting_changed", properties: [
            "setting_id": id,
            "value_type": "number",
            "value": value,
            "surface": surface,
        ])
    }

    /// Enum-valued setting committed by the user (fixed vocabularies:
    /// alphabet ids, palettes, fonts, permitted engine values).
    public static func setting(_ id: String, _ value: String, surface: String) {
        AnalyticsService.shared.capture("setting_changed", properties: [
            "setting_id": id,
            "value_type": "enum",
            "value": value,
            "surface": surface,
        ])
    }

    /// RFC 0001 v1 event: the user picked an alphabet (fixed vocabulary).
    public static func alphabetSelected(_ id: String) {
        AnalyticsService.shared.capture("alphabet_selected", properties: ["alphabet_id": id])
    }

    /// Free-text/string setting committed by the user — the VALUE is never
    /// collected (RFC 0001 amendment: file paths and custom text excluded);
    /// only the fact of the change and its surface.
    public static func stringSettingChanged(_ id: String, surface: String) {
        AnalyticsService.shared.capture("setting_changed", properties: [
            "setting_id": id,
            "value_type": "string",
            "surface": surface,
        ])
    }
}
