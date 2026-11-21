#!/usr/bin/env bash
# vol.sh up|down|mute|micmute - volume keys (also a headset volume wheel) with the step and ceiling from Settings > Sound.
# Fast and in order: no python, and flock lines the presses up - a quickly turned wheel sends many events at once,
# and parallel "read volume, add 5" calls used to overwrite each other, so turns got lost.
S="$HOME/.config/sakura/settings.json"
step=$(grep -o '"volStep": *[0-9]*' "$S" 2>/dev/null | grep -o '[0-9]*$'); step=${step:-5}
max=$(grep -o '"volMax": *[0-9]*' "$S" 2>/dev/null | grep -o '[0-9]*$'); max=${max:-100}
RUN="${XDG_RUNTIME_DIR:-/tmp}"
# hold up|down / release: a headset volume wheel "holds" the key while it turns, so a fast spin used to give a single
# step (the key repeat starts only after 600 ms). Now: one step at once, then steps every 45 ms until the key is let go.
case "$1" in
  release) rm -f "$RUN/sakura-vol-hold"; exit 0 ;;
  hold)    dir="$2"; echo $$ > "$RUN/sakura-vol-hold"
           "$0" "$dir"
           ( sleep 0.12; while [ "$(cat "$RUN/sakura-vol-hold" 2>/dev/null)" = "$$" ]; do "$0" "$dir"; sleep 0.045; done ) &
           exit 0 ;;
esac
# the level shows in the top bar's notch (quickshell Notch.qml: it also sees every change itself, this call is
# for the ceiling, where nothing changes). Not running, or the bar is at the bottom → swayosd as before.
# At most one call per 0.3 s: a spinning wheel steps every 45 ms.
osd() {     # osd volume|mic "swayosd args"
  local now last; now=$(date +%s%N); last=$(cat "$RUN/sakura-osd-t" 2>/dev/null || echo 0)
  [ $((now - last)) -lt 300000000 ] && [ "$3" != force ] && return
  echo "$now" > "$RUN/sakura-osd-t"
  r=$(timeout 1 qs ipc call osd "$1" 2>/dev/null)
  [ "$r" = ok ] || swayosd-client $2 >/dev/null 2>&1
}
exec 9>"$RUN/sakura-vol.lock"
flock 9
# wpctl changes the volume right away (swayosd-client only hands it to its server, which can drop quick ones)
lim=$(awk "BEGIN{print $max/100}")
case "$1" in
  up)   wpctl set-volume -l "$lim" @DEFAULT_AUDIO_SINK@ "$step%+"; wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 ;;
  down) wpctl set-volume @DEFAULT_AUDIO_SINK@ "$step%-" ;;
  mute)    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
  micmute) wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
esac
flock -u 9
case "$1" in
  mute)    osd volume "--output-volume +0" force ;;
  micmute) osd mic "--input-volume +0" force ;;
  *)       osd volume "--output-volume +0" & ;;
esac
