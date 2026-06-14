# Regenerate docs/demo.gif with: cd docs && vhs demo.tape
#
# Uses a deterministic fake agent (demo-fakebin/pi) so the recording is
# reproducible and does not depend on a live model. The rendering pipeline,
# typo classification, and safe-rm confirmation flow are all the real thing.
Output "demo.gif"

Set Shell "zsh"
Set FontSize 18
Set Width 1100
Set Height 600
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms

# Setup (hidden): put the fake agent first on PATH, load the shellish hook
# (vhs starts a non-interactive zsh that doesn't read ~/.zshrc), make sample
# PNGs in a scratch dir, clear the screen.
Hide
Type "export DEMO=$(pwd)" Enter
Type "export PATH=$DEMO/demo-fakebin:$HOME/.local/bin:$PATH" Enter
Type "source $HOME/.local/share/shellish/shell/zshrc.zsh" Enter
Type "cd $(mktemp -d)" Enter
Type "for i in 1 2 3; do sips -s format png -z $((400+i*200)) $((400+i*200)) /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns --out photo_$i.png >/dev/null 2>&1; done" Enter
Type "clear" Enter
Show

Sleep 1s

# 1) Just type at the prompt — no command, no flags. Any language works.
Type "shrink every png in this folder" Sleep 400ms Enter
Sleep 5s

# 2) A typo is caught and corrected, never executed.
Type "gti status" Sleep 400ms Enter
Sleep 3s

# 3) Deletes go to the trash, with a confirm — answer N to cancel.
Type "delete all the png files" Sleep 400ms Enter
Sleep 4s
Type "N" Sleep 400ms Enter
Sleep 2.5s

Sleep 1.5s
