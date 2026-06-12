# Walkthrough: walk the dependency graph. Rendered by recording/record.sh
# against a fresh demo bd DB.

Output "/work/assets/usage/graph.gif"

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

# Down to the epic, open it.
Down Sleep 500ms
Down Sleep 700ms
Enter
Sleep 1800ms

# Sidebar -> graph for this issue, then the all-issues view.
Tab
Sleep 1200ms
Type "D" Sleep 2400ms
Type "a" Sleep 2400ms

Type "q" Sleep 500ms
Type ":qa!" Enter
Sleep 800ms
