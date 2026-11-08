# dmgbuild settings for the AlwaysOn installer window.
#
# Used by Scripts/build-dmg.sh, which passes:
#   -D app=<AlwaysOn.app>  -D layout=<layout.json>  -D background=<folder with background.png and background@2x.png>
# dmgbuild writes the Finder layout (.DS_Store) directly, so no Finder or
# AppleScript session is needed on the CI runner.
import json
import os

app = defines["app"]  # noqa: F821
with open(defines["layout"]) as fp:  # noqa: F821
    L = json.load(fp)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}

# dmgbuild pairs background.png with background@2x.png into one HiDPI TIFF
background = os.path.join(defines["background"], "background.png")  # noqa: F821

# Volume icon: the app's own icon, when the build produced one
icon_path = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
if os.path.exists(icon_path):
    icon = icon_path

# Open at the full art height; only the top windowHeight is guaranteed visible
window_rect = ((200, 120), (L["windowWidth"], L["windowHeight"] + L["bleed"]))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = L["iconSize"]
text_size = 13
label_pos = "bottom"
arrange_by = None
icon_locations = {
    os.path.basename(app): (L["appX"], L["iconY"]),
    "Applications": (L["applicationsX"], L["iconY"]),
}
