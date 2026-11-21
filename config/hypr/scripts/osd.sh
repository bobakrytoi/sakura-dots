#!/usr/bin/env bash
# (re)start the volume/brightness OSD (swayosd) where Settings > Notifications says: "osdPos" top | center | bottom
p=$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get("osdPos","bottom"))' "$HOME/.config/sakura/settings.json" 2>/dev/null)
case "$p" in top) m=0.08 ;; center) m=0.5 ;; *) m=0.85 ;; esac
pkill -x swayosd-server; sleep 0.2
setsid -f swayosd-server --top-margin "$m" >/dev/null 2>&1
