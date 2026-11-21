#!/usr/bin/env bash
# clipboard history watchers (cliphist), following Settings > Screenshots & recording > Clipboard:
#   clipMax (entries kept), clipImages (store pictures), clipSkipSecret (skip passwords from password managers),
#   clipWipeLogin (start every session empty). Run again after a change: it restarts the watchers.
read -r max imgs secret wipe < <(python3 -I -c 'import json,sys
try: c = json.load(open(sys.argv[1]))
except Exception: c = {}
print(c.get("clipMax", 750), int(c.get("clipImages", True)), int(c.get("clipSkipSecret", True)), int(c.get("clipWipeLogin", False)))' "$HOME/.config/sakura/settings.json" 2>/dev/null)
pkill -f 'wl-paste --type (text|image) --watch' 2>/dev/null
[ "$1" = login ] && [ "${wipe:-0}" = 1 ] && cliphist wipe
store="cliphist -max-items ${max:-750} store"
# password managers mark their copies with x-kde-passwordManagerHint: leave those out
[ "${secret:-1}" = 1 ] && store="wl-paste --list-types | grep -q x-kde-passwordManagerHint || $store"
setsid -f wl-paste --type text --watch sh -c "$store" >/dev/null 2>&1
[ "${imgs:-1}" = 1 ] && setsid -f wl-paste --type image --watch sh -c "$store" >/dev/null 2>&1
exit 0
