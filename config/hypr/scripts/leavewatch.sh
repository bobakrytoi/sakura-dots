#!/usr/bin/env bash
# sakura - lets the shell play its "fold away" (bar and dock slide into their edges, the screen dims) before ANY
# sleep / shutdown / reboot, however it was started (power button, systemctl in a terminal, hypridle, the shell).
# Holds a logind *delay* inhibitor; logind announces PrepareForSleep/PrepareForShutdown and waits for it (max
# InhibitDelayMaxSec, 5 s by default). Prints one word per event for quickshell (Choreo.qml runs this script):
#   away sleep | away shutdown   → fold, then the lock is let go after $HOLD s
#   back                         → woke up: grow back
HOLD=0.8
ipid=""
take() { systemd-inhibit --what=sleep:shutdown --mode=delay --who="sakura shell" --why="fold-away animation" tail --pid=$$ -f /dev/null & ipid=$!; }   # dies with this script, never left behind
drop() { [ -n "$ipid" ] && kill "$ipid" 2>/dev/null; ipid=""; }
trap 'drop; exit 0' EXIT INT TERM
take
while read -r line; do
    case "$line" in
        *PrepareForSleep*true*)     echo "away sleep";    sleep "$HOLD"; drop ;;
        *PrepareForSleep*false*)    take; echo "back" ;;
        *PrepareForShutdown*true*)  echo "away shutdown"; sleep "$HOLD"; drop ;;
        *PrepareForShutdown*false*) take; echo "back" ;;      # shutdown cancelled
    esac
done < <(gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1)
