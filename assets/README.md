# Artwork

Source images. They are **not** shipped in the addon zip (only `GuildAssistant/` is).

| File | What | Used for |
|---|---|---|
| `guild_logo.png` | Guild Assistant emblem, full colour on a dark background, 1024x1024 | source of `GuildAssistant/Media/guild_logo.tga` (window header, minimap button, AddOns list icon) and the README header |

## Regenerating the game texture

WoW does not load PNG. It loads TGA or BLP with power-of-two sides. `tools/make_tga.swift` (macOS, needs the Swift
toolchain) centres an image on a transparent square canvas and writes a 32-bit uncompressed TGA with straight alpha:

```bash
swift tools/make_tga.swift assets/guild_logo.png GuildAssistant/Media/guild_logo.tga 128 0
```

The last two arguments are the canvas size in pixels (a power of two) and the margin as a fraction of it.
The logo is already square and carries its own background, so it uses no margin.
