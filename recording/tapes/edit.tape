# Walkthrough: open & edit an issue (the detail buffer IS the description).
# Rendered by recording/record.sh against a fresh demo bd DB.

Output "/work/assets/usage/edit.gif"

Set Shell bash
Set FontSize 16
Set Width 1200
Set Height 720
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 70ms

Hide
Type "cd /demo && clear" Enter
Type "nvim -u /work/recording/init.lua" Enter
Sleep 2s
Show

Type ":Beads" Sleep 300ms Enter
Sleep 1800ms
Down Sleep 600ms
Enter
Sleep 1800ms

# The detail view is a real, always-editable buffer — vim keys just work.
Type "Go" Sleep 400ms
Type "- TODO: add a test for the unsupported-card fallback" Sleep 500ms
Escape Sleep 700ms

# :w persists via `bd update --body-file -`.
Type ":w" Sleep 200ms Enter
Sleep 1800ms

Type ":qa!" Enter
Sleep 800ms
