#!/usr/bin/env bash
# builds a locale in your home folder (no root needed), e.g.  sakura-locale.sh ru  -> ~/.local/share/sakura-locale/ru_RU.UTF-8
# waybar (dates) and, if you choose so in Settings, every app (after re-login) use it through LOCPATH.
D="$HOME/.local/share/sakura-locale"
case "${1:-en}" in ru) L=ru_RU ;; uk) L=uk_UA ;; de) L=de_DE ;; *) L=en_US ;; esac
mkdir -p "$D"
for loc in en_US "$L"; do
  [ -d "$D/$loc.UTF-8" ] || localedef -i "$loc" -f UTF-8 "$D/$loc.UTF-8" 2>/dev/null
done
echo "$L.UTF-8"
