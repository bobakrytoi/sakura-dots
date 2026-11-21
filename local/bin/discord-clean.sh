#!/usr/bin/env bash
# Чистит сетевой кэш Discord и запускает его.
# Local Storage / сессия НЕ трогаются - из аккаунта не выкидывает.
set -u

DIR="$HOME/.config/discord"
if [ -d "$DIR" ]; then
    rm -rf \
        "$DIR/Cache" \
        "$DIR/Code Cache" \
        "$DIR/GPUCache" \
        "$DIR/DawnGraphiteCache" \
        "$DIR/DawnWebGPUCache" \
        "$DIR/GPUPersistentCache" \
        "$DIR/Shared Dictionary" \
        "$DIR/Service Worker/CacheStorage" \
        2>/dev/null
fi

# Cloudflare sometimes blocks the Discord app (by its user agent) from a given Mullvad exit IP:
# "Temporary Network Error". Then reconnect Mullvad (another server in the same country, VPN stays on).
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) discord/1.0 Chrome/138.0 Electron/37.0 Safari/537.36"
if command -v mullvad >/dev/null && mullvad status 2>/dev/null | grep -q Connected; then
    for _ in 1 2 3 4 5 6; do
        [ "$(curl -s -o /dev/null -w '%{http_code}' -A "$UA" --max-time 8 https://discord.com/app)" = 403 ] || break
        mullvad reconnect >/dev/null 2>&1; sleep 4
    done
fi

exec /usr/bin/discord "$@"
