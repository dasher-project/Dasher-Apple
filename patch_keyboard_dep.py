#!/usr/bin/env python3
"""Post-xcodegen patch — no longer needed.

Previously added PBXTargetDependency + PBXCopyFilesBuildPhase for
embedding DasherKeyboard in DasherApp. Now handled natively by
xcodegen via `embed: true` in project.yml.

Kept as a no-op for CI compatibility.
"""
print("No patch needed — embed handled by xcodegen")
