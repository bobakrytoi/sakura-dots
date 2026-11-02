#!/usr/bin/env bash
# minimize: hide | restore | restore-addr <address> | count
case "$1" in
  hide)
    hyprctl eval "local w = hl.get_active_window()
      if w then
        __min_skip = w.address
        hl.dispatch(hl.dsp.window.move({ workspace = 'special:minimized', window = 'address:' .. w.address, follow = false }))
        hl.timer(function() __min_skip = nil end, { timeout = 600, type = 'oneshot' })
      end" >/dev/null
    pkill -RTMIN+8 waybar ;;
  hide-addr)
    a="$2"; [[ "$a" == 0x* ]] || a="0x$a"
    hyprctl eval "__min_skip = '$a'
      hl.dispatch(hl.dsp.window.move({ workspace = 'special:minimized', window = 'address:$a', follow = false }))
      hl.timer(function() __min_skip = nil end, { timeout = 600, type = 'oneshot' })" >/dev/null
    pkill -RTMIN+8 waybar ;;
  restore-addr)
    a="$2"; [[ "$a" == 0x* ]] || a="0x$a"
    hyprctl eval "local m = hl.get_active_monitor()
      local sp = m.active_special_workspace
      if sp and sp.name == 'special:minimized' then hl.dispatch(hl.dsp.workspace.toggle_special('minimized')) end
      hl.dispatch(hl.dsp.window.move({ workspace = tostring(m.active_workspace.id), window = 'address:$a' }))
      hl.dispatch(hl.dsp.focus({ window = 'address:$a' }))
      hl.dispatch(hl.dsp.window.bring_to_top())
      local w = hl.get_window('address:$a')
      if w then local p, z = w.at, w.size; hl.dispatch(hl.dsp.cursor.move({ x = (p.x or p[1]) + (z.x or z[1]) / 2, y = (p.y or p[2]) + (z.y or z[2]) / 2 })) end" >/dev/null
    pkill -RTMIN+8 waybar ;;
  restore)
    list=$(hyprctl clients -j | python3 -c '
import json,sys
for c in json.load(sys.stdin):
    if c["workspace"]["name"]=="special:minimized":
        t=c["title"] if len(c["title"])<60 else c["title"][:57]+"…"
        print(c["address"]+"\t"+c["class"]+"  —  "+t)')
    [ -z "$list" ] && exit 0
    if [ "$(printf '%s\n' "$list" | wc -l)" -eq 1 ]; then sel=$(printf '%s' "$list" | cut -f1)
    else sel=$(printf '%s\n' "$list" | rofi -dmenu -i -p "minimized" -display-columns 2 -display-column-separator '\t' -theme ~/.config/rofi/list.rasi | cut -f1); fi
    [ -n "$sel" ] && exec "$0" restore-addr "$sel" ;;
  count)
    n=$(hyprctl clients -j | python3 -c 'import json,sys;print(sum(1 for c in json.load(sys.stdin) if c["workspace"]["name"]=="special:minimized"))')
    if [ "$n" -gt 0 ]; then printf '{"text":"\U000f05b0  %s","tooltip":"Minimized windows — click to restore"}\n' "$n"; else echo '{"text":""}'; fi ;;
esac
