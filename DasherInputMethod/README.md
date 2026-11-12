# Dasher Direct Input

Dasher Direct Input is a macOS input source. It provides up to 256 UTF-16 units before the editor's selection. Direct Mode uses the read to update the language model. Accessibility supplies context when the input source has no read for the editor. The existing keyboard path sends text and Backspace.

The input source sends context over a local socket in the macOS app group. Both processes check the other process's signing identity. The socket carries no write commands. The helper does not read during marked text composition or secure keyboard input.

## Use Direct Mode

1. Open Dasher. Choose **Direct Mode** from the layout menu.
2. If macOS asks for access, enable Dasher in **System Settings → Privacy & Security**. Open **Device Control and Data Access** on macOS 27. Open **Accessibility** on earlier versions.
3. If Dasher shows **Improve Predictions in Other Apps**, you can click **Open Keyboard Settings**. Under **Text Input**, click **Edit**, then click **+**. Search for **Dasher Direct Input** and click **Add**.
4. Click the field where you want to type. Steer with the Dasher canvas.
5. To return to the editor in Dasher, click **Toggle keyboard mode** or close the Direct Mode canvas.

Dasher installs its bundled input source in the user's Input Methods folder. It selects the source during Direct Mode when macOS makes the source available. If the source is still active when Direct Mode ends, Dasher restores the previous keyboard source.

If **Dasher Direct Input** is missing from Keyboard Settings, restart your Mac and check the list again. To skip this step, click **Later**. Click **Set Up Text Context** in the canvas to show the instructions again.

## Check context in Direct Mode

1. Enable **Advanced logging** in Dasher settings. Enter Direct Mode.
2. Focus a scratch document in BBEdit. Move the caret forward and backward in a sentence with the arrow keys. Then click in a different sentence. Pause for one second after each move.
3. Check `keyboard_debug.log` for `[InputMethodKit] read` and a context seed for each new position. The log records the caret position in the editor and the length of the text that Dasher reads.
4. Repeat with [the browser scratch fields](Tests/BrowserFields.html). Switch between fields, including fields with the same text. Check that Dasher reads from the current field.
5. Click or steer the Dasher canvas. Check that the editor retains keyboard focus and receives output.
6. Leave Direct Mode. Check that the previous input source is active. Repeat the check when you quit Dasher in Direct Mode.
7. Select your usual input source while Direct Mode is active. Check that Dasher reads through Accessibility in an editor that supports it.

## Build and sign

Generate the Xcode project with `xcodegen generate`. Build the `DasherMac` scheme. It embeds `Dasher Direct Input.app` in `Dasher.app/Contents/Helpers`. The macOS release workflow signs the input source before it signs the outer app. Both use the same team and each uses its own entitlements file.
