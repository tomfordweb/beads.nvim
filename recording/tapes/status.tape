# Walkthrough: change an issue's status from the sidebar. Rendered by
# recording/record.sh against a fresh demo bd DB.

Output "/work/assets/usage/status.gif"

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

# Toggle to the sidebar — issue actions live here on the editable view.
Tab
Sleep 1500ms

# `s` runs the status action; pick a new status from the select list. The demo
# issue is in_progress; pick blocked (3rd in `bd statuses`) for a visible change.
Type "s" Sleep 1300ms
Type "3" Sleep 400ms Enter
Sleep 2200ms

Type ":qa!" Enter
Sleep 800ms
