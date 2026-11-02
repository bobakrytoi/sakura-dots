#!/usr/bin/env bash
# bottom dock, always visible on the main monitor
pkill -f '^nwg-dock-hyprland' 2>/dev/null; sleep 0.3
exec nwg-dock-hyprland -x -o DP-3 -i 36 -mb 8 -c "__HOME__/.config/hypr/scripts/menu.sh" -ico view-app-grid-symbolic -lp start -iw special
