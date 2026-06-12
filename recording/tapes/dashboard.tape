# Walkthrough: project status at a glance (:BeadsDashboard). Rendered by
# recording/record.sh against a fresh demo bd DB.

Output "/work/assets/usage/dashboard.gif"

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

# Home dashboard: status counts, ready, total from `bd stats`.
Type ":BeadsDashboard" Sleep 300ms Enter
Sleep 3s

# Jump straight into the open-issue picker from the dashboard.
Type "o" Sleep 2200ms

Escape Sleep 300ms
Escape Sleep 300ms
Type ":qa!" Enter
Sleep 800ms
