# Dasher macOS input method probe

This standalone probe tests mouse-only access to the focused editor through InputMethodKit. Its floating panel belongs to the input method process.

**Read Context** checks the selection and reads up to 32 UTF-16 units before it. **Insert Marker** replaces the selection with `DasherProbe`. **Delete Marker** deletes that marker immediately before the caret. Each edit needs a fresh context read. The panel shows ranges and results. It does not display or log editor text.

## Build and install

Run these commands from the repository root on macOS 14 or later. The build signs the app locally and runs the text tests.

```sh
Tools/InputMethodProbe/build.sh
probe_app="$HOME/Library/Input Methods/Dasher IME Probe.app"
mkdir -p "$HOME/Library/Input Methods"
ditto "build/input-method-probe/Dasher IME Probe.app" "$probe_app"
probe="$probe_app/Contents/MacOS/DasherInputMethodProbe"
previous_source=$("$probe" current)
"$probe" register
"$probe" enable
"$probe" status
```

Select **Dasher IME Probe** from the macOS Input menu. If the menu does not show the probe, add it in **System Settings → Keyboard → Text Input → Edit**. If it still does not appear, sign out and sign back in before testing again.

## Live test

Use scratch text. The first three checks need mouse clicks only after you select the input source.

| Check | Action | Expected result |
| --- | --- | --- |
| Activate without a key press | Open TextEdit with `😀 left replace right`. Select the probe input source. Click in the text. | The panel appears. **Read Context** shows the editor caret. Clicking the panel leaves the editor focused. |
| Replace a selection | Double-click `replace`. Click **Read Context**, then **Insert Marker**. | The text becomes `😀 left DasherProbe right`. The panel shows `Insert readback matched.` |
| Delete by range | Click **Read Context**. Click **Delete Marker**. | The marker disappears. Both surrounding spaces stay in place. The panel shows `Delete readback matched.` |
| Reject a moved caret | Read at one position. Click at another position. Click **Insert Marker** without a fresh read. | The probe requests a fresh read. The text stays the same. |
| Switch identical fields | Open `fixture.html` in Safari or Chrome. Read one field, then click at the same position in the other field. Click **Insert Marker**. | The text in both fields stays the same. The probe requests a fresh read. |
| Switch apps | Read in TextEdit. Focus a different editor. Click **Insert Marker** without a fresh read. | The probe requests a fresh read. Neither editor changes. |
| Check a secure field | Click the secure field in `fixture.html`. | The probe hides its panel or reports that context is unavailable. |
| Check physical typing | Type a letter in a scratch field with the probe selected. | The editor receives the letter once. |

Repeat the activation, replacement, deletion, and caret checks in Safari and Chrome. Use both regular and rich text fields in `fixture.html`. Repeat the same checks in VS Code and BBEdit. Record the app version, macOS version, and result for each app.

Check the resulting text in the editor after each edit. The panel checks the caret and text before it. The panel cannot check changes elsewhere in the document.

If the panel reports `Delete unconfirmed`, record the rest of the message and check whether `DasherProbe` remains in the editor. The probe checks again if the editor returns its old caret and text. It sends the delete only once.

## Results so far

The build, code signature, and mock-client tests passed on macOS 27.3. macOS registered, enabled, and selected the input source. The previous input source was restored.

The live test confirmed insertion in TextEdit and Safari. The original probe could not confirm deletion in TextEdit. The new status shows which part of the readback differs. Repeat the delete test before Dasher uses this path in Direct Mode.

## Restore your input source

If you still have the setup shell, run the commands below. Otherwise, select your previous input source in the Input menu. Then disable the probe and move it to Trash.

```sh
"$probe" select "$previous_source"
"$probe" disable
mv "$probe_app" "$HOME/.Trash/Dasher IME Probe-$(date +%Y%m%d-%H%M%S).app"
```
