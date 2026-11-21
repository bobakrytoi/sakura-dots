#!/usr/bin/env bash
# sakura mono - archives from Dolphin's right-click menu (servicemenus/sakura-archive.desktop) without Ark.
#   archive.sh ui FILES…                         → open the Compress dialog (quickshell Archive.qml)
#   archive.sh compress FMT LEVEL NAME FILES…     → FMT zip|7z|tar.zst|tar.gz|tar.xz · LEVEL fast|normal|max
#        password (zip/7z only) comes on stdin, never on the command line of this script
#   archive.sh extract here|folder FILES…        → 7z / tar; a password-protected one asks via the dialog
#   archive.sh extractpw MODE FILE               → same, password on stdin
# Tools: 7z (7zip), tar, zstd, xz, gzip. Done / failed → a notification.
set -u
mode="${1:-}"; shift || true
abs() { local o=() f; for f in "$@"; do case "$f" in /*) o+=("$f") ;; *) o+=("$PWD/$f") ;; esac; done; printf '%s\n' "${o[@]}"; }
note() { notify-send -a "Archive" -i "${3:-package-x-generic}" "$1" "$2" 2>/dev/null; }
q() { printf '%s' "$1" | sed 's/[&<>]/ /g'; }

case "$mode" in
ui)
    [ $# -gt 0 ] || exit 1
    list=$(abs "$@")
    qs ipc call archive compress "$list" >/dev/null 2>&1 || note "Archive" "The shell isn't running" dialog-error ;;

compress)
    fmt="$1" lvl="$2" name="$3"; shift 3
    [ $# -gt 0 ] || exit 1
    IFS= read -r pw || pw=""
    dir=$(dirname -- "$1")
    base="${name:-$(basename -- "$1")}"; base="${base//\//_}"
    out="$dir/$base.$fmt"; n=2
    while [ -e "$out" ]; do out="$dir/$base ($n).$fmt"; n=$((n + 1)); done
    rel=(); for f in "$@"; do rel+=("$(basename -- "$f")"); done
    case "$lvl" in fast) x=1 z=3 g=1 ;; max) x=9 z=19 g=9 ;; *) x=5 z=10 g=6 ;; esac
    note "Compressing…" "$(q "$(basename -- "$out")")" package-x-generic
    cd -- "$dir" || exit 1
    case "$fmt" in
        zip) if [ -n "$pw" ]; then 7z a -tzip -mx="$x" -mem=AES256 -p"$pw" -- "$out" "${rel[@]}"; else 7z a -tzip -mx="$x" -- "$out" "${rel[@]}"; fi ;;
        7z)  if [ -n "$pw" ]; then 7z a -t7z -mx="$x" -mhe=on -p"$pw" -- "$out" "${rel[@]}"; else 7z a -t7z -mx="$x" -- "$out" "${rel[@]}"; fi ;;
        tar.zst) tar -I "zstd -T0 -$z$([ "$z" -gt 19 ] && echo ' --ultra')" -cf "$out" -- "${rel[@]}" ;;
        tar.gz)  tar -I "gzip -$g" -cf "$out" -- "${rel[@]}" ;;
        tar.xz)  tar -I "xz -T0 -$g" -cf "$out" -- "${rel[@]}" ;;
        *) note "Archive" "Unknown format $fmt" dialog-error; exit 1 ;;
    esac >/dev/null 2>"/tmp/sakura-archive.err"
    if [ $? -eq 0 ]; then
        note "Archive ready" "$(q "$(basename -- "$out")") · $(du -h -- "$out" | cut -f1)" package-x-generic
    else
        rm -f -- "$out"; note "Couldn't compress" "$(q "$(tail -2 /tmp/sakura-archive.err)")" dialog-error; exit 1
    fi ;;

extract|extractpw)
    how="$1"; shift
    mapfile -t _f < <(abs "$@"); set -- "${_f[@]}"
    pw=""; [ "$mode" = extractpw ] && { IFS= read -r pw || pw=""; }
    for f in "$@"; do
        dir=$(dirname -- "$f"); b=$(basename -- "$f")
        stem="$b"; for e in .tar.zst .tar.gz .tar.xz .tar.bz2 .tgz .txz .tar .zip .7z .rar .zst .gz .xz .bz2; do
            case "${stem,,}" in *"$e") stem="${stem:0:${#stem}-${#e}}"; break ;; esac; done
        dest="$dir"
        if [ "$how" = folder ]; then dest="$dir/$stem"; n=2; while [ -e "$dest" ]; do dest="$dir/$stem ($n)"; n=$((n + 1)); done; fi
        mkdir -p -- "$dest"
        case "${b,,}" in
            *.tar|*.tar.*|*.tgz|*.txz|*.tbz2) tar -xf "$f" -C "$dest" ;;
            *) 7z x -y -aou -p"$pw" -o"$dest" -- "$f" ;;
        esac >/dev/null 2>"/tmp/sakura-archive.err" </dev/null
        rc=$?
        if [ $rc -ne 0 ] && grep -qiE "wrong password|encrypted|can not open encrypted" /tmp/sakura-archive.err; then
            [ "$how" = folder ] && rmdir -- "$dest" 2>/dev/null
            qs ipc call archive password "$how" "$f" >/dev/null 2>&1
            [ -n "$pw" ] && note "Wrong password" "$(q "$b")" dialog-error
            continue
        fi
        if [ $rc -eq 0 ]; then note "Extracted" "$(q "$b") → $(q "$(basename -- "$dest")")" package-x-generic
        else [ "$how" = folder ] && rmdir -- "$dest" 2>/dev/null; note "Couldn't extract" "$(q "$(tail -2 /tmp/sakura-archive.err)")" dialog-error; fi
    done ;;

*) echo "usage: archive.sh ui|compress|extract|extractpw …"; exit 1 ;;
esac
