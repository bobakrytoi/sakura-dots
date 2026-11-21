#!/usr/bin/env bash
# Restart ONLY the main shell (~/.config/quickshell); other qs instances (Sakura Sound player…) stay alive.
#   qs-restart.sh          → kill main instance(s) by config path, start one fresh from $HOME
main="$HOME/.config/quickshell/shell.qml"
for pid in $(qs list --all 2>/dev/null | awk -v m="$main" '/Process ID:/{p=$3} /Config path:/{if($3==m) print p}'); do kill "$pid" 2>/dev/null; done
pkill -x quickshell 2>/dev/null          # the old binary name never runs the player
sleep 1.5
(cd "$HOME" && setsid -f qs -d >/dev/null 2>&1)
sleep 2
n=$(qs list --all 2>/dev/null | grep -c "Config path: $main")
echo "main instances: $n"
