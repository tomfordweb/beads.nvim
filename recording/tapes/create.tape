# Walkthrough: create an issue (:BeadsCreate form). Rendered by
# recording/record.sh against a fresh demo bd DB.

Output "/work/assets/usage/create.gif"

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

# Interactive form: title -> type -> priority -> deps -> bd create.
Type ":BeadsCreate" Sleep 300ms Enter
Sleep 1500ms

# Title
Type "Add saved payment methods" Sleep 600ms Enter
Sleep 1500ms

# Type (numbered select — first option)
Type "1" Sleep 400ms Enter
Sleep 1300ms

# Priority (P2 normal = 3rd label)
Type "3" Sleep 400ms Enter
Sleep 1300ms

# Deps — skip
Enter
Sleep 2800ms

Type ":qa!" Enter
Sleep 800ms
