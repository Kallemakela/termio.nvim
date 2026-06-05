## Width issues

The overlay window width is currently either
- `prompt` which starts at prompt, even if multiline, making it a bit ugly and quite annoying if the width ends up being small
- `start` which hides the prompt

`prompt` editor is implemented to solve this issue and is now recommended instead of overlay.

Remaining overlay-specific idea:
1. Make two floating windows, use prompt as starting point for first line, start for the rest `./plan-two-floating-windows.md`
    - mega hack
