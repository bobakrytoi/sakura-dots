#!/usr/bin/env bash
# AyuGram: the prebuilt AUR package is broken (404), so build the official one from source.
# Takes ~30-60 min, uses all CPU cores.
export MAKEFLAGS="-j$(nproc)"
yay -S --needed --noconfirm --answerdiff None --answerclean None --sudoloop ayugram-desktop && echo "DONE! Tell Claude."
