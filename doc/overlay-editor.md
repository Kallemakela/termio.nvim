## Width issues

Places an overlay window on the row where the latest osc133 B marker is
detected. Uses `buftype=prompt` to include the prompt as non-modifiable text.

Smoothest editing experience since jitter is hidden behind the window.

Some hacks required to make focus transitions between overlay window and the
target terminal window seamless.
- Like if user tries to open a buffer in the editor window, the window is
closed and buffer is opened in the target window
./../lua/termio/editors/fixbuf.lua
