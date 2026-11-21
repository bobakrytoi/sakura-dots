#!/usr/bin/env bash
# minimize: hide | hide-addr <address> | restore | restore-addr <address> | count
#   hide / hide-addr / restore-addr play the flight into / out of the top bar's notch (quickshell Genie.qml), which then
#   calls hide-now / restore-now at the right moment; without quickshell they just do it (no animation).
# hide-now / restore-now happen under Genie's flying picture: Hyprland's own window animations would show behind it
# (a fading ghost, a slide from the other monitor), so they are off for a moment. Nested calls count, the value from
# before is put back through hyprctl eval (from a timer, i.e. an event handler, Hyprland ignores it - see game mode).
QUIET="if not __minQuiet then
  function __minQuiet(ms)
    if (__minQuietN or 0) == 0 then local ok, v = pcall(hl.get_config, 'animations.enabled'); __minAnimWas = (not ok) or v ~= false end
    __minQuietN = (__minQuietN or 0) + 1
    hl.config({ animations = { enabled = false } })
    hl.timer(function()
      __minQuietN = __minQuietN - 1
      if __minQuietN == 0 and not __gameMode then hl.exec_cmd(\"hyprctl eval 'hl.config({ animations = { enabled = \" .. tostring(__minAnimWas) .. \" } })'\") end
    end, { timeout = ms, type = 'oneshot' })
  end
end"
geom() {   # address -> "x y w h" of that window now
  hyprctl clients -j | python3 -I -c 'import json,sys
a = sys.argv[1]
for c in json.load(sys.stdin):
    if c["address"] == a: print(*c["at"], *c["size"]); break' "$1"
}
case "$1" in
  hide)
    a=$(hyprctl activewindow -j | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("address", ""))' 2>/dev/null)
    [ -n "$a" ] && exec "$0" hide-addr "$a" ;;
  hide-addr)
    a="$2"; [[ "$a" == 0x* ]] || a="0x$a"
    read -r x y w h <<<"$(geom "$a")"
    if [ -n "$h" ]; then qs ipc call genie eat "$a" "$x" "$y" "$w" "$h" >/dev/null 2>&1 && exit 0; fi
    exec "$0" hide-now "$a" ;;
  hide-now)
    a="$2"; [[ "$a" == 0x* ]] || a="0x$a"
    hyprctl eval "$QUIET
      __minQuiet(350)
      __min_skip = '$a'
      __minSave('$a')
      hl.dispatch(hl.dsp.window.move({ workspace = 'special:minimized', window = 'address:$a', follow = false }))
      hl.timer(function() __min_skip = nil end, { timeout = 600, type = 'oneshot' })" >/dev/null
    pkill -RTMIN+8 waybar ;;
  restore-addr)
    a="$2"; [[ "$a" == 0x* ]] || a="0x$a"
    # where it lands: its saved place (~/.cache/sakura/minimized: address float x y w h …), else its size in the
    # middle of the focused monitor
    read -r x y w h < <(awk -v a="$a" '$1 == a { print $3, $4, $5, $6; exit }' "$HOME/.cache/sakura/minimized" 2>/dev/null)
    if [ -z "$h" ]; then
      read -r x y w h < <(hyprctl -j clients | python3 -I -c 'import json,sys,subprocess
a = sys.argv[1]
c = next((c for c in json.load(sys.stdin) if c["address"] == a), None)
ms = json.loads(subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True).stdout)
m = next((m for m in ms if m["focused"]), ms[0])
if c:
    w, h = c["size"]; mw, mh = m["width"] / m["scale"], m["height"] / m["scale"]
    print(int(m["x"] + (mw - w) / 2), int(m["y"] + (mh - h) / 2), w, h)' "$a")
    fi
    if [ -n "$h" ]; then qs ipc call genie spit "$a" "$x" "$y" "$w" "$h" >/dev/null 2>&1 && exit 0; fi
    exec "$0" restore-now "$a" ;;
  restore-now)
    a="$2"; [[ "$a" == 0x* ]] || a="0x$a"
    hyprctl eval "$QUIET
      __minQuiet(350)
      local m = hl.get_active_monitor()
      local sp = m.active_special_workspace
      if sp and sp.name == 'special:minimized' then hl.dispatch(hl.dsp.workspace.toggle_special('minimized')) end
      __minBack('$a', m.active_workspace.id)
      hl.dispatch(hl.dsp.focus({ window = 'address:$a' }))
      hl.dispatch(hl.dsp.window.bring_to_top())" >/dev/null
    pkill -RTMIN+8 waybar ;;
  restore)
    # one window: straight back; more: the glass picker (minimize-pick.py → quickshell minimize-qs, rofi fallback)
    list=$(hyprctl clients -j | python3 -c '
import json,sys
for c in json.load(sys.stdin):
    if c["workspace"]["name"]=="special:minimized": print(c["address"])')
    [ -z "$list" ] && exit 0
    if [ "$(printf '%s\n' "$list" | wc -l)" -eq 1 ]; then sel=$list
    else sel=$("$(dirname "$0")/minimize-pick.py"); fi
    [ -n "$sel" ] && exec "$0" restore-addr "$sel" ;;
  count)
    n=$(hyprctl clients -j | python3 -c 'import json,sys;print(sum(1 for c in json.load(sys.stdin) if c["workspace"]["name"]=="special:minimized"))')
    if [ "$n" -gt 0 ]; then printf '{"text":"\U000f05b0  %s","tooltip":"Minimized windows - click to restore"}\n' "$n"; else echo '{"text":""}'; fi ;;
esac
