on run argv
    set mounted to POSIX file (item 1 of argv) as alias
    tell application "Finder"
        open mounted
        set w to front Finder window
        set current view of w to icon view
        set toolbar visible of w to false
        set statusbar visible of w to false
        set bounds of w to {160, 100, 800, 522}
        set options to icon view options of w
        set arrangement of options to not arranged
        set icon size of options to 96
        set text size of options to 14
        set background picture of options to file ".background:install.png" of mounted
        set position of item "Sage Keys.app" of mounted to {160, 190}
        set position of item "Applications" of mounted to {480, 190}
        update mounted without registering applications
        delay 2
        close w
    end tell
end run
