#!/usr/bin/env python3
"""Post-xcodegen patch: add DasherKeyboard as a target dependency of DasherApp.

XCodeGen creates the "Embed Foundation Extensions" build phase but doesn't
create the PBXTargetDependency from DasherApp -> DasherKeyboard.
Without this, xcodebuild won't build the keyboard before embedding it.
"""

import re
import sys

PROJECT = "Dasher.xcodeproj/project.pbxproj"

APP_TARGET = "A82A5F19DDAFE41BE1623B1C"
KB_TARGET = "2378E43FAAFC72D2083199A7"
DEP_UID = "A1B2C3D4E5F6A7B8C9D0E1F2"
PROXY_UID = "F2E1D0C9B8A7F6E5D4C3B2A1"
PROJECT_OBJECT = "6C792BE950B016EC79DB68FF"

with open(PROJECT, "r") as f:
    content = f.read()

# Already patched?
if DEP_UID in content:
    print("Already patched")
    sys.exit(0)

# 1. Add PBXContainerItemProxy
marker = "/* End PBXContainerItemProxy section */"
proxy_entry = f"""\t\t{PROXY_UID} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {PROJECT_OBJECT} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {KB_TARGET};
\t\t\tremoteInfo = DasherKeyboard;
\t\t}};\n"""
content = content.replace(marker, proxy_entry + marker)

# 2. Add PBXTargetDependency
marker = "/* End PBXTargetDependency section */"
dep_entry = f"""\t\t{DEP_UID} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {KB_TARGET} /* DasherKeyboard */;
\t\t\ttargetProxy = {PROXY_UID} /* PBXContainerItemProxy */;
\t\t}};\n"""
content = content.replace(marker, dep_entry + marker)

# 3. Add to DasherApp's dependencies array
pattern = rf"({APP_TARGET}.*?dependencies = \()(.*?)(\);)"
def add_dep(m):
    existing = m.group(2).rstrip()
    if existing and not existing.endswith(","):
        existing += ","
    return m.group(1) + existing + f"\n\t\t\t\t{DEP_UID} /* PBXTargetDependency */," + "\n\t\t\t" + m.group(3)

content = re.sub(pattern, add_dep, content, count=1, flags=re.DOTALL)

# 4. Add "Embed Foundation Extensions" phase to DasherApp's buildPhases
# First check if it already exists
EMBED_PHASE = "7827EF5C8DC50E15919AA33B"
if EMBED_PHASE not in content[max(0, content.find(APP_TARGET)):content.find(APP_TARGET)+5000]:
    # Find DasherApp's buildPhases and add the embed phase after Frameworks
    bp_pattern = rf"({APP_TARGET}.*?buildPhases = \()(.*?)(\);)"
    def add_embed_phase(m):
        existing = m.group(2).rstrip()
        if existing and not existing.endswith(","):
            existing += ","
        return m.group(1) + existing + f"\n\t\t\t\t{EMBED_PHASE} /* Embed Foundation Extensions */," + "\n\t\t\t" + m.group(3)
    content = re.sub(bp_pattern, add_embed_phase, content, count=1, flags=re.DOTALL)
    print("Added Embed Foundation Extensions phase to DasherApp buildPhases")

with open(PROJECT, "w") as f:
    f.write(content)

print("Patched: added DasherKeyboard dependency to DasherApp target")
