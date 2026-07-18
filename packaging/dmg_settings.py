# dmgbuild settings for the release DMG (invoked by scripts/release.sh).
#
# dmgbuild writes the window's .DS_Store directly instead of driving Finder
# over AppleScript, which is what makes a styled DMG reproducible in CI —
# the AppleScript approach needs a UI session and TCC automation consent, and
# is the usual reason DMG styling is flaky on hosted runners.
#
# Coordinates are Finder's: origin at the window content's top-left, and each
# icon location is the icon's *centre*. They must stay in sync with the
# backdrop drawn by scripts/generate_art.swift (drawDMGBackground).

import os.path

# Injected by release.sh via -D.
application = defines["app"]
app_name = os.path.basename(application)

filesystem = "HFS+"
format = "UDZO"
size = None

files = [application]
symlinks = {"Applications": "/Applications"}

# The volume icon, so the mounted disk shows the app's own icon.
badge_icon = None
icon = defines.get("volume_icon")

background = defines["background"]

window_rect = ((160, 160), (660, 400))
default_view = "icon-view"
icon_size = 128
text_size = 13
label_pos = "bottom"

icon_locations = {
    app_name: (165, 185),
    "Applications": (495, 185),
}

# Chrome off: the backdrop carries the instructions.
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
