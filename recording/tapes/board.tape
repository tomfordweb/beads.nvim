# Walkthrough: the kanban board. Rendered by recording/record.sh against a
# fresh demo bd DB. See recording/README.md.

Output "/work/assets/usage/board.gif"

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

# Lay every issue out as status columns: open / in progress / blocked / closed.
Type ":BeadsBoard" Sleep 300ms Enter
Sleep 2200ms

# Move across columns with l, then back — focus jumps column to column.
Type "l" Sleep 900ms
Type "l" Sleep 900ms
Type "h" Sleep 700ms
Type "h" Sleep 900ms

# Pick a card in the open column and move it to another status. Each column
# leads with a header + blank line, so step down to the first card row before
# acting. `s` opens the status select; the card is open, so pick blocked (3rd)
# — it slides into the (until now empty) blocked column.
Type "j" Sleep 250ms
Type "j" Sleep 700ms
Type "s" Sleep 1200ms
Type "3" Sleep 400ms Enter
Sleep 2200ms

# Hop over to the blocked column to see the card landed there.
Type "l" Sleep 800ms
Type "l" Sleep 2000ms

Type "q" Sleep 500ms
Type ":qa!" Enter
Sleep 800ms
