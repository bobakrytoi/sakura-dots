# sakura ambient - фоновые звуки для барабана (EdgeTab → «Фоновые звуки»)

Все записи - **CC0 1.0 (public domain dedication)**, https://creativecommons.org/publicdomain/zero/1.0/
Скачаны 2026-11-19 с freesound.org (HQ-превью), затем обрезаны, выровнены по громкости
(ffmpeg loudnorm I=-26) и склеены в бесшовную петлю (4 с кроссфейд конца в начало), ogg vorbis q4.

| файл        | исходник                                                        | автор            | лицензия |
|-------------|-----------------------------------------------------------------|------------------|----------|
| rain.ogg    | https://freesound.org/people/speakwithanimals/sounds/525046/ «Rain Slowly Passing TREATED LOOP» | speakwithanimals | CC0 |
| fire.ogg    | https://freesound.org/people/moxobna/sounds/62487/ «1103campfire1.wav» | moxobna | CC0 |
| cafe.ogg    | https://freesound.org/people/priesjensen/sounds/482990/ «People talking at cafe ambience» | priesjensen | CC0 |
| forest.ogg  | https://freesound.org/people/bajko/sounds/385280/ «sfx_amb_forest_spring_afternoon-01.wav» | bajko | CC0 |
| waves.ogg   | https://freesound.org/people/Noted451/sounds/531015/ «Ocean Waves.wav» | Noted451 | CC0 |

Шум (белый / розовый / коричневый) файлов не имеет: генерируется на лету
`mpv av://lavfi:anoisesrc=color=…` (ffmpeg), лицензий не требует.

Чтобы добавить звук: положи сюда `<id>.ogg` и допиши строку в `sounds` в ~/.config/quickshell/Ambient.qml.
