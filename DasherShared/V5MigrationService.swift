import Foundation

/// Extended bridge protocol for migration — adds setAlphabetId for pending support.
public protocol DasherBridgeProtocol: AccessSettingsBridge {
    func setAlphabetId(_ id: String)
}

#if os(macOS)

/// Result of a v5 migration scan — what was found and whether it was imported.
public struct V5MigrationResult {
    public var foundSettings: Bool
    public var foundCustomFiles: [String]
    public var foundTrainingFiles: [String]
    public var importedSettings: [(name: String, value: String)]
    public var skippedSettings: [(name: String, reason: String)]
    public var importedFiles: [String]
    public var skippedFiles: [(name: String, reason: String)]
    /// Parameters that must be applied AFTER engine Realize (they trigger
    /// engine handlers that crash if called before Realize).
    public var deferredParameters: [(key: Int, value: String)]

    public init() {
        foundSettings = false
        foundCustomFiles = []
        foundTrainingFiles = []
        importedSettings = []
        skippedSettings = []
        importedFiles = []
        skippedFiles = []
        deferredParameters = []
    }

    public var hasData: Bool {
        foundSettings || !foundCustomFiles.isEmpty || !foundTrainingFiles.isEmpty
    }
}

/// Detects and imports Dasher v5 settings and user data on macOS.
///
/// Per RFC 0005: reads the v5 plist from
/// `~/Library/Preferences/uk.ac.cam.phy.inference.dasher.plist` and
/// copies custom files from `~/Library/Application Support/Dasher/`.
public struct V5MigrationService {

    private static let v5BundleID = "uk.ac.cam.phy.inference.dasher"

    // In a sandboxed app, NSHomeDirectory() returns the container path.
    // We need the real home directory to find v5 data.
    private static let realHomeDir: String = {
        "/Users/\(NSUserName())"
    }()

    private static let v5PlistPath: String = {
        "\(realHomeDir)/Library/Preferences/\(v5BundleID).plist"
    }()
    private static let v5UserDataDir: String = {
        "\(realHomeDir)/Library/Application Support/Dasher"
    }()

    // MARK: - UserDefaults keys (version-gated)

    // Stores the app version at the time migration was offered/completed.
    // If the app version changes (update installed), the version comparison
    // fails and the migration is re-offered — so users who ran a broken
    // migration on an earlier build get another chance.
    private static let offeredVersionKey = "dasher.v5_migration_offered_version"
    private static let completedVersionKey = "dasher.v5_migration_completed_version"

    private static var currentAppVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    public static var hasBeenOffered: Bool {
        UserDefaults.standard.string(forKey: offeredVersionKey) == currentAppVersion
    }

    public static var hasBeenCompleted: Bool {
        UserDefaults.standard.string(forKey: completedVersionKey) == currentAppVersion
    }

    // MARK: - Detection

    /// Scans for v5 data without importing. Returns what was found.
    public static func scan() -> V5MigrationResult {
        var result = V5MigrationResult()

        // Check for v5 plist
        let plist = NSDictionary(contentsOfFile: v5PlistPath)
        result.foundSettings = plist != nil && (plist?.count ?? 0) > 0

        // Scan user data dir for custom files
        let fm = FileManager.default
        if fm.fileExists(atPath: v5UserDataDir),
           let entries = try? fm.contentsOfDirectory(atPath: v5UserDataDir) {
            for entry in entries {
                if entry.hasPrefix("alphabet.") && entry.hasSuffix(".xml") {
                    result.foundCustomFiles.append("Alphabet: \(entry)")
                } else if entry.hasPrefix("colour.") && entry.hasSuffix(".xml") {
                    result.foundCustomFiles.append("Colour: \(entry)")
                } else if entry.hasPrefix("color.") && entry.hasSuffix(".xml") {
                    result.foundCustomFiles.append("Colour: \(entry)")
                } else if entry.hasPrefix("control.") && entry.hasSuffix(".xml") {
                    result.foundCustomFiles.append("Control: \(entry)")
                } else if entry.hasPrefix("training_") && entry.hasSuffix(".txt") {
                    result.foundTrainingFiles.append(entry)
                }
            }
        }

        return result
    }

    // MARK: - Import

    /// Imports v5 settings and user data. Call BEFORE dasher_set_screen_size().
    /// - Parameters:
    ///   - bridge: The Dasher bridge to apply settings to
    ///   - userDir: v6 user data directory (to copy files into)
    /// - Returns: Detailed migration result
    public static func importSettings(
        bridge: AccessSettingsBridge,
        userDir: String
    ) -> V5MigrationResult {
        var result = scan()

        guard result.hasData else { return result }

        // 1. Import settings from v5 plist
        if result.foundSettings, let plist = NSDictionary(contentsOfFile: v5PlistPath) {
            importPlistSettings(plist, bridge: bridge, result: &result)
        }

        // 2. Copy custom user files
        copyUserDataFiles(to: userDir, result: &result)

        // 3. Mark as complete (version-gated)
        UserDefaults.standard.set(currentAppVersion, forKey: offeredVersionKey)
        UserDefaults.standard.set(currentAppVersion, forKey: completedVersionKey)

        return result
    }

    /// Marks migration as offered without importing (user clicked "Not now").
    public static func markOffered() {
        UserDefaults.standard.set(currentAppVersion, forKey: offeredVersionKey)
    }

    // MARK: - Plist import

    /// Parameters that trigger engine actions via HandleEvent — must NOT be
    /// set before Realize (they dereference null pointers like m_pNCManager).
    private static let deferredParamNames: Set<String> = [
        "BP_CONTROL_MODE",
        "SP_INPUT_FILTER",
    ]

    private static func importPlistSettings(
        _ plist: NSDictionary,
        bridge: AccessSettingsBridge,
        result: inout V5MigrationResult
    ) {
        // Bool parameters: v5 regName → v6 enum name
        let boolMap: [String: String] = [
            "DrawMouseLine": "BP_DRAW_MOUSE_LINE",
            "DrawMouse": "BP_DRAW_MOUSE",
            "CurveMouseLine": "BP_CURVE_MOUSE_LINE",
            "StartOnLeft": "BP_START_MOUSE",
            "StartOnSpace": "BP_START_SPACE",
            "ControlMode": "BP_CONTROL_MODE",
            "PaletteChange": "BP_PALETTE_CHANGE",
            "TurboMode": "BP_TURBO_MODE",
            "ExactDynamics": "BP_EXACT_DYNAMICS",
            "Autocalibrate": "BP_AUTOCALIBRATE",
            "RemapXtreme": "BP_REMAP_XTREME",
            "AutoSpeedControl": "BP_AUTO_SPEEDCONTROL",
            "LMAdaptive": "BP_LM_ADAPTIVE",
            "NonlinearY": "BP_NONLINEAR_Y",
            "PauseOutside": "BP_STOP_OUTSIDE",
            "BackoffButton": "BP_BACKOFF_BUTTON",
            "TwoButtonReverse": "BP_TWOBUTTON_REVERSE",
            "TwoButtonInvertDouble": "BP_2B_INVERT_DOUBLE",
            "SlowStart": "BP_SLOW_START",
            "CopyOnStop": "BP_COPY_ALL_ON_STOP",
            "SpeakOnStop": "BP_SPEAK_ALL_ON_STOP",
            "SpeakWords": "BP_SPEAK_WORDS",
            "SlowControlBox": "BP_SLOW_CONTROL_BOX",
        ]

        for (regName, enumName) in boolMap {
            if let value = plist[regName] as? Bool {
                let key = bridge.findParameterKey(enumName)
                if key >= 0 {
                    if deferredParamNames.contains(enumName) {
                        result.deferredParameters.append((key, "\(value)"))
                    } else {
                        bridge.setBoolParameter(key: key, value: value)
                    }
                    result.importedSettings.append((regName, "\(value)"))
                }
            }
        }

        // Long parameters
        let longMap: [String: String] = [
            "ScreenOrientation": "LP_ORIENTATION",
            "MaxBitRateTimes100": "LP_MAX_BITRATE",
            "UniformTimes1000": "LP_UNIFORM",
            "LMAlpha": "LP_LM_ALPHA",
            "LMBeta": "LP_LM_BETA",
            "LMMaxOrder": "LP_LM_MAX_ORDER",
            "LMExclusion": "LP_LM_EXCLUSION",
            "LMUpdateExclusion": "LP_LM_UPDATE_EXCLUSION",
            "LMMixture": "LP_LM_MIXTURE",
            "LineWidth": "LP_LINE_WIDTH",
            "Zoomsteps": "LP_ZOOMSTEPS",
            "NodeBudget": "LP_NODE_BUDGET",
            "MarginWidth": "LP_MARGIN_WIDTH",
            "TargetOffset": "LP_TARGET_OFFSET",
            "XLimitSpeed": "LP_X_LIMIT_SPEED",
            "MinNodeSize": "LP_MIN_NODE_SIZE",
            "OutlineWidth": "LP_OUTLINE_WIDTH",
            "NonLinearX": "LP_NONLINEAR_X",
            "AutospeedSensitivity": "LP_AUTOSPEED_SENSITIVITY",
            "Geometry": "LP_GEOMETRY",
            "WordAlpha": "LP_LM_WORD_ALPHA",
            "MessageFontSize": "LP_MESSAGE_FONTSIZE",
            "RenderStyle": "LP_SHAPE_TYPE",
            "CirclePercent": "LP_CIRCLE_PERCENT",
            "TwoButtonOffset": "LP_TWO_BUTTON_OFFSET",
            "HoldTime": "LP_HOLD_TIME",
            "MultipressTime": "LP_MULTIPRESS_TIME",
            "SlowStartTime": "LP_SLOW_START_TIME",
            "TapTime": "LP_TAP_TIME",
            "ClickMaxZoom": "LP_MAXZOOM",
            "DynamicSpeedInc": "LP_DYNAMIC_SPEED_INC",
            "DynamicSpeedFreq": "LP_DYNAMIC_SPEED_FREQ",
            "DynamicSpeedDec": "LP_DYNAMIC_SPEED_DEC",
            "MousePositionBoxDistance": "LP_MOUSEPOSDIST",
        ]

        for (regName, enumName) in longMap {
            if let value = plist[regName] as? Int {
                let key = bridge.findParameterKey(enumName)
                if key >= 0 {
                    bridge.setLongParameter(key: key, value: value)
                    result.importedSettings.append((regName, "\(value)"))
                }
            }
        }

        // Special: DasherFontSize transformation (v5 index → v6 points)
        if let fontSizeIndex = plist["DasherFontSize"] as? Int {
            let points = transformFontSize(fontSizeIndex)
            let key = bridge.findParameterKey("LP_DASHER_FONTSIZE")
            if key >= 0 {
                bridge.setLongParameter(key: key, value: points)
                result.importedSettings.append(("DasherFontSize", "\(fontSizeIndex) → \(points)pt"))
            }
        }

        // Special: Start mode (CircleStart / StartOnMousePosition → LP_START_MODE)
        let circleStart = plist["CircleStart"] as? Bool ?? false
        let mousePosMode = plist["StartOnMousePosition"] as? Bool ?? false
        let startModeKey = bridge.findParameterKey("LP_START_MODE")
        if startModeKey >= 0 {
            let startMode: Int
            if circleStart {
                startMode = 2 // circle_start
            } else if mousePosMode {
                startMode = 1 // mouse_pos_start
            } else {
                startMode = 0 // none
            }
            if circleStart || mousePosMode {
                bridge.setLongParameter(key: startModeKey, value: startMode)
                result.importedSettings.append(("StartMode", "→ \(startMode)"))
            }
        }

        // String parameters
        let stringMap: [String: String] = [
            "AlphabetID": "SP_ALPHABET_ID",
            "DasherFont": "SP_DASHER_FONT",
            "GameTextFile": "SP_GAME_TEXT_FILE",
            "InputFilter": "SP_INPUT_FILTER",
            "InputDevice": "SP_INPUT_DEVICE",
            "Alphabet1": "SP_ALPHABET_1",
            "Alphabet2": "SP_ALPHABET_2",
            "Alphabet3": "SP_ALPHABET_3",
            "Alphabet4": "SP_ALPHABET_4",
        ]

        for (regName, enumName) in stringMap {
            if let value = plist[regName] as? String, !value.isEmpty {
                let key = bridge.findParameterKey(enumName)
                if key >= 0 {
                    if deferredParamNames.contains(enumName) || enumName == "SP_ALPHABET_ID" {
                        result.deferredParameters.append((key, value))
                    } else {
                        bridge.setStringParameter(key: key, value: value)
                    }
                }
                result.importedSettings.append((regName, value))
            }
        }

        // Special: ColourID (empty string → "Default")
        if let colourID = plist["ColourID"] as? String, !colourID.isEmpty {
            let key = bridge.findParameterKey("SP_COLOUR_ID")
            if key >= 0 {
                bridge.setStringParameter(key: key, value: colourID)
                result.importedSettings.append(("ColourID", colourID))
            }
        }

        // Track skipped settings
        let knownKeys = Set(boolMap.keys).union(longMap.keys).union(stringMap.keys).union(["DasherFontSize", "CircleStart", "StartOnMousePosition", "ColourID"])
        let platformKeys: Set<String> = [
            "AppStyle", "EditFont", "EditFontSize", "EditHeight", "EditWidth",
            "FileEncodingFormat", "FullScreen", "MirrorLayout", "PopupEnable",
            "PopupFont", "PopupFullScreen", "PopupInfront", "ScreenHeight",
            "ScreenHeightH", "ScreenWidth", "ScreenWidthH", "TimeStampNewFiles",
            "ToolbarID", "ViewStatusbar", "ViewToolbar", "WindowState", "XPosition",
            "YPosition", "ConfirmUnsavedFiles",
        ]
        for key in plist.allKeys {
            let keyStr = key as? String ?? ""
            if !knownKeys.contains(keyStr) {
                if platformKeys.contains(keyStr) {
                    result.skippedSettings.append((keyStr, "Platform-specific UI setting (not applicable in v6)"))
                } else {
                    result.skippedSettings.append((keyStr, "Unknown or unsupported parameter"))
                }
            }
        }
    }

    /// v5 font size index → v6 point size
    private static func transformFontSize(_ index: Int) -> Int {
        switch index {
        case 0: return 14
        case 1: return 18
        case 2: return 22
        case 3: return 28
        case 4: return 36
        default: return min(index * 8, 72)
        }
    }

    // MARK: - File copy

    private static func copyUserDataFiles(to destDir: String, result: inout V5MigrationResult) {
        let fm = FileManager.default

        guard fm.fileExists(atPath: v5UserDataDir) else { return }

        guard let entries = try? fm.contentsOfDirectory(atPath: v5UserDataDir) else { return }

        // Ensure dest + subdirs exist
        let subdirs = ["alphabets", "colours", "control", "training"]
        try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        for sub in subdirs {
            try? fm.createDirectory(atPath: "\(destDir)/\(sub)", withIntermediateDirectories: true)
        }

        for entry in entries {
            // Route to the correct v6 subdirectory (matching DasherCore's ScanFiles layout).
            let subdir: String
            let overwrite: Bool

            if entry.hasPrefix("alphabet.") && entry.hasSuffix(".xml") {
                subdir = "alphabets"; overwrite = false
            } else if (entry.hasPrefix("colour.") || entry.hasPrefix("color.")) && entry.hasSuffix(".xml") {
                subdir = "colours"; overwrite = false
            } else if entry.hasPrefix("control.") && entry.hasSuffix(".xml") {
                // control.xml overwrites the bundled default — user's custom tree wins
                subdir = "control"; overwrite = true
            } else if entry.hasPrefix("training_") && entry.hasSuffix(".txt") {
                subdir = "training"; overwrite = false
            } else {
                continue
            }

            let srcPath = "\(v5UserDataDir)/\(entry)"
            let destPath = "\(destDir)/\(subdir)/\(entry)"

            if fm.fileExists(atPath: destPath) && !overwrite {
                result.skippedFiles.append((entry, "File already exists in v6 \(subdir)/"))
            } else {
                do {
                    if fm.fileExists(atPath: destPath) {
                        try fm.removeItem(atPath: destPath)
                    }
                    try fm.copyItem(atPath: srcPath, toPath: destPath)
                    result.importedFiles.append(entry)
                } catch {
                    result.skippedFiles.append((entry, "Copy failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// Applies deferred parameters after the engine has been realized.
    /// Call this after `startEngine()` / `dasher_set_screen_size()`.
    public static func applyDeferredParameters(_ params: [(key: Int, value: String)], bridge: AccessSettingsBridge) {
        for (key, value) in params {
            // Try as bool first, then long, then string
            if value == "true" || value == "false" {
                bridge.setBoolParameter(key: key, value: value == "true")
            } else if let intVal = Int(value) {
                bridge.setLongParameter(key: key, value: intVal)
            } else {
                bridge.setStringParameter(key: key, value: value)
            }
        }
    }

    // MARK: - Reset (for testing)

    /// Resets migration state so it can be re-offered. For testing/debugging.
    public static func resetMigrationState() {
        UserDefaults.standard.removeObject(forKey: offeredVersionKey)
        UserDefaults.standard.removeObject(forKey: completedVersionKey)
    }
}

#endif // os(macOS)
