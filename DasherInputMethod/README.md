# Dasher Direct Input test

Dasher Direct Input is a macOS input source. It provides up to 256 UTF-16 units before the editor's selection. Direct Mode uses the read to update the language model. Accessibility supplies context when the input source has no read for the editor. The existing keyboard path sends text and Backspace.

The input source sends context over a local socket in the macOS app group. Both processes check the other process's signing identity. The socket carries no write commands. The helper does not read during marked text composition or secure keyboard input.

## Run the staged build

Use the signed app at `build/direct-input-test/Dasher.app`. Quit any running copy of Dasher before opening this build.

Run these commands from the repository root to install and register the input source.

```sh
dasher_app="$PWD/build/direct-input-test/Dasher.app"
method_app="$HOME/Library/Input Methods/Dasher Direct Input.app"
mkdir -p "$HOME/Library/Input Methods"
ditto "$dasher_app/Contents/Helpers/Dasher Direct Input.app" "$method_app"
"$method_app/Contents/MacOS/Dasher Direct Input" register
open "$dasher_app"
```

In **System Settings → Keyboard → Text Input → Edit**, add **Dasher Direct Input**. Select it from the Input menu with the editor in front.

## Check context in Direct Mode

1. Enable **Advanced logging** in Dasher settings. Enter Direct Mode.
2. Focus a scratch document in BBEdit. Move the caret between two different sentences. Pause after each move.
3. Check `keyboard_debug.log` for `[InputMethodKit] read` and a context seed for the new caret position. The log records lengths and positions.
4. Repeat in a browser text field. Switch between fields, including fields with the same text. Check that Dasher reads from the current field.
5. Click or steer the Dasher canvas. Check that the editor retains keyboard focus and receives output.
6. Switch to your usual input source. Check that Direct Mode reads through Accessibility in an editor that supports it.

The test build uses the current Direct Mode window. The canvas focus check and release packaging still need verification. The standalone probe remains available for comparison.

## Build both products

Generate the Xcode project with `xcodegen generate`. Build the `DasherMac` and `DasherInputMethod` schemes for macOS. Sign both with the same Dasher team. Use each target's own entitlements file. For a test bundle, place the signed `Dasher Direct Input.app` in `Dasher.app/Contents/Helpers` before signing `Dasher.app`.
