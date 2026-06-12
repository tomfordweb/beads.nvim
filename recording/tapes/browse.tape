# Walkthrough: browse & filter issues. Rendered by recording/record.sh against
# a fresh demo bd DB. See recording/README.md.

Output "/work/assets/usage/browse.gif"

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

# Open the picker over `bd list`.
Type ":Beads" Sleep 300ms Enter
Sleep 2s

# Move through the list.
Down Sleep 500ms
Down Sleep 700ms

# Cycle the live filters (status, then type) — client-side, no refetch.
Ctrl+S Sleep 1600ms
Ctrl+S Sleep 1600ms
Ctrl+T Sleep 1600ms

# Type to filter by text.
Type "stripe" Sleep 1800ms

Escape Sleep 300ms
Escape Sleep 300ms
Type ":qa!" Enter
Sleep 800ms
