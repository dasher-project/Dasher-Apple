# Dasher Direct Input

Dasher Direct Input is a macOS input source. It provides up to 256 UTF-16 units before the editor's selection. Direct Mode uses the read to update the language model. Accessibility supplies context when the input source has no read for the editor. The existing keyboard path sends text and Backspace.

The input source sends context over a local socket in the macOS app group. Both processes check the other process's signing identity. The socket carries no write commands. The helper does not read during marked text composition or secure keyboard input.

## Use Direct Mode

1. Open Dasher. Choose **Direct Mode** from the layout menu.
2. If macOS asks for access, enable Dasher in **System Settings → Privacy & Security**. Open **Device Control and Data Access** on macOS 27. Open **Accessibility** on earlier versions.
3. For better predictions, open **Input → Set Up Text Context** from the Dasher menu bar. Select **Open Keyboard Settings**. Under **Text Input**, select **Edit**. Then select **+**. Search for **Dasher Direct Input**. Select **Add**.
4. Click the field where you want to type. Steer with the Dasher canvas.
5. To return to the editor in Dasher, select **Input → Toggle keyboard mode** or close the Direct Mode canvas.

Dasher installs its input source in your Input Methods folder. If you use one other keyboard source, Dasher can select Dasher Direct Input for you. If Dasher selected the source and it is still active at exit, Dasher restores the previous source.

macOS can remember an input source for each document. Dasher cannot restore the source in a document that does not have focus.

If you use more than one other keyboard source, focus an editor. Then select **Dasher Direct Input** from the macOS Input menu. If a document still uses **Dasher Direct Input** after exit, select your usual source from the same menu.

If **Dasher Direct Input** is missing from Keyboard Settings, restart your Mac. Then look for the source again. To skip the optional setup, select **Later**. Dasher uses Accessibility to read text if the input source is unavailable.

## Check context in Direct Mode

1. Enable **Advanced logging** in Dasher settings. Enter Direct Mode.
2. Focus a scratch document in BBEdit. Move the caret forward and backward in a sentence with the arrow keys. Then click in a different sentence. Pause for one second after each move.
3. Check `keyboard_debug.log` for `[InputMethodKit] read` and a context seed for each new position. The log records the caret position in the editor and the length of the text that Dasher reads.
4. Repeat in a browser text field. Switch between two fields with different caret positions. Check that Dasher reads from the current field.
5. Click or steer the Dasher canvas. Check that the editor retains keyboard focus and receives output.
6. With one other keyboard source enabled, leave Direct Mode. Check that the previous input source is active. Repeat the check when you quit Dasher in Direct Mode.
7. Select your usual input source while Direct Mode is active. Check that Dasher reads through Accessibility in an editor that supports it.

## Build and sign

Generate the Xcode project with `xcodegen generate`. Build the `DasherMac` scheme. It embeds `Dasher Direct Input.app` in `Dasher.app/Contents/Helpers`. The macOS release workflow signs the input source before it signs the outer app. Both use the same team and each uses its own entitlements file.
