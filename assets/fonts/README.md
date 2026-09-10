# UI font

`yizhe-ui-subset.ttf` is a weight-400 subset of Noto Sans SC generated from
the runtime text in this project. The upstream variable font comes from the
Google Fonts `ofl/notosanssc` directory. Redistribution and modification are
covered by the SIL Open Font License 1.1 in `OFL.txt`.

When user-facing text gains new characters, regenerate the subset before a
release so those glyphs remain available in Web exports:

```powershell
& '.\tools\build_ui_font.ps1'
```
