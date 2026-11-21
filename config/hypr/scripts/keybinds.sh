#!/usr/bin/env bash
# keybind cheatsheet (read from hyprctl)
hyprctl binds -j | python3 -c '
import json,sys
mods=[(64,"SUPER"),(4,"CTRL"),(8,"ALT"),(1,"SHIFT")]
seen=set()
for b in json.load(sys.stdin):
    d=b.get("description")
    if not d: continue
    m=" + ".join(n for bit,n in mods if b["modmask"]&bit)
    k=(m+" + " if m else "")+b["key"]
    if (k,d) in seen: continue
    seen.add((k,d)); print(f"{k:<26}  {d}")
' | rofi -dmenu -i -p "keybinds" -theme ~/.config/rofi/list.rasi >/dev/null
