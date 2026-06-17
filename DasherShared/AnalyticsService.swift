import Foundation
import PostHog
#if canImport(UIKit)
import UIKit
#endif

/// Privacy-preserving analytics wrapper around PostHog.
/// All events are opt-in. No typed text, clipboard, or PII is ever sent.
///
/// Mirrors `AnalyticsService.cs` from Dasher-Windows for feature parity (RFC 0001).
public final class AnalyticsService {
    public static let shared = AnalyticsService()

    private static let projectToken = "phc_ubtNRuCT7Zqo4dVrVWRnJRYE9m9WqGeTyK7zVDKQ968J"
    private static let host = "https://eu.i.posthog.com"

    private var settings = AnalyticsSettings()
    private var distinctId = ""
    private var initialized = false

    private init() {}

    public var isOptedIn: Bool { settings.optedIn }
    public var hasPrompted: Bool { settings.promptShown }
    public var anonymousId: String { distinctId }

    public func initialize() {
        settings = AnalyticsSettings.load()
        distinctId = settings.getOrCreateAnonymousId()

        if !settings.optedIn { return }

        startPostHog()
    }

    private func startPostHog() {
        guard !initialized else { return }
        initialized = true

        let config = PostHogConfig(apiKey: Self.projectToken, host: Self.host)
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
    }

    public func setOptIn(_ optedIn: Bool) {
        settings.optedIn = optedIn
        settings.promptShown = true
        settings.save()

        if optedIn {
            startPostHog()
            capture("analytics_opted_in")
        }
    }

    public func resetAnonymousId() {
        let wasOptedIn = settings.optedIn
        if wasOptedIn {
            capture("analytics_id_reset")
        }

        settings.resetAnonymousId()
        distinctId = settings.getOrCreateAnonymousId()
    }

    /// Returns the default properties appended to every event so all frontends
    /// can be distinguished in the shared PostHog project.
    private func defaultProperties() -> [String: Any] {
        var props: [String: Any] = [
            "platform": platformName,
            "app_variant": appVariant,
            "app_version": appVersion,
        ]

        #if canImport(UIKit)
        props["os_version"] = UIDevice.current.systemVersion
        #elseif canImport(AppKit)
        props["os_version"] = ProcessInfo.processInfo.operatingSystemVersionString
        #endif

        return props
    }

    private var platformName: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #elseif os(visionOS)
        return "visionos"
        #else
        return "unknown"
        #endif
    }

    private var appVariant: String {
        #if os(iOS)
        return "dasher-ios"
        #elseif os(macOS)
        return "dasher-mac"
        #elseif os(visionOS)
        return "dasher-vision"
        #else
        return "dasher-unknown"
        #endif
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// Capture an analytics event. No-ops if the user has not opted in.
    /// Platform, app_variant, app_version and os_version are auto-included.
    /// NEVER pass typed text, clipboard contents, or PII as properties.
    public func capture(_ eventName: String, properties: [String: Any]? = nil) {
        guard settings.optedIn, initialized else { return }

        var props = defaultProperties()
        if let extra = properties {
            for (k, v) in extra { props[k] = v }
        }

        PostHogSDK.shared.capture(eventName, distinctId: distinctId, properties: props)
    }

    /// Capture a crash/exception. Called from uncaught exception handlers.
    public func captureCrash(_ error: Error) {
        guard settings.optedIn, initialized else { return }

        var props = defaultProperties()
        props["stack_trace"] = String(describing: error)
        PostHogSDK.shared.capture("crash", distinctId: distinctId, properties: props)
    }

    public func flush() {
        guard initialized else { return }
        PostHogSDK.shared.flush()
    }
}
