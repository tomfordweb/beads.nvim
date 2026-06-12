# VHS tape for the README demo GIF (E9). Drives the real beads.nvim UI against
# a throwaway demo bd DB seeded from tests/fixtures/demo/ (synthetic data — no
# personal info on screen). Rendered headlessly by recording/record.sh inside
# the VHS container; cwd at run time is the seeded demo dir so the plugin finds
# its .beads. Re-record per Neovim version by rebuilding the image and re-running.
#
#   vhs https://github.com/charmbracelet/vhs

Output "/work/assets/demo.gif"

Set Shell bash
Set FontSize 16
Set Width 1200
Set Height 720
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 70ms

# Enter the seeded demo dir (so the plugin resolves /demo/.beads) and launch
# into the clean recording config. VHS starts its own shell, so cd explicitly
# rather than trusting the inherited cwd.
Hide
Type "cd /demo && clear" Enter
Type "nvim -u /work/recording/init.lua" Enter
Sleep 2s
Show

# Issue browser: Telescope picker over `bd list`. Move down to the epic.
Type ":Beads" Sleep 400ms Enter
Sleep 2s
Down Sleep 700ms
Down Sleep 900ms

# Open the epic's editable detail view + the issue sidebar (the picker stays
# open behind the float; never Escape or it closes the view onto the picker).
Enter
Sleep 2500ms

# Toggle to the sidebar (overview / children / actions) and read it. The detail
# buffer is a real editable buffer, so action keys live here on the sidebar —
# never send them to the view or vim eats them as edits.
Tab
Sleep 2500ms

# Dependency graph (sidebar 'D' = graph), then toggle to the all-issues view.
Type "D"
Sleep 2500ms
Type "a"
Sleep 2500ms

# Tear everything down (buffer is untouched, so no save prompt).
Type "q" Sleep 800ms
Type ":qa!" Enter
Sleep 1s
