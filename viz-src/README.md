# Answer visuals (HyperFrames)

Sources for the looping charts shown under Muse's sample answers (assets/viz-*.mp4|webm|jpg).

- Built with HyperFrames (motion-graphics workflow), 960x540, 6s, 30fps, dark data panel, language-neutral labels.
- `generate.py` + `common.css` write one composition per visual; each `viz-*.html` is that composition.
- Re-render: put a file in a HyperFrames project as `index.html`, then
  `npx hyperframes check . && npx hyperframes render . -q high -o renders/video.mp4`
- WebM fallback: `ffmpeg -i viz-x.mp4 -c:v libvpx-vp9 -b:v 0 -crf 38 -an viz-x.webm`
- Poster: `ffmpeg -ss 5.5 -i viz-x.mp4 -frames:v 1 viz-x.jpg`

| file | answer |
|---|---|
| viz-drake | "What matters right now?" — drake countdown + win chance |
| viz-flash | "Why did they lose that fight?" — summoner spells + 3–0 |
| viz-gold | "Who made the gold lead?" — wGE+ by role |
| viz-comeback | "Is this comeback real?" — win chance line 41% → 63% |
