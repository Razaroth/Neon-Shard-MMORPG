# Cyberpunk RPG sprite conversion

The original Neon Shard class designs are redrawn as chunky pixel-RPG sprites. New generated artwork preserves their recognizable colors, costumes, hair and weapons. LPC body/animation templates guide pose and direction. Generated art is a prototype, not a guarantee of artist-cleaned frame consistency.

Each class has `walk.png` (9 columns: idle then 8 steps), `run.png` (8 columns) and `attack.png` (6 columns). Four rows face north, west, south and east. The game uses measured row separators and cached polygons around each pose to prevent neighboring heads, boots or weapon tips bleeding into a frame, retains distance-based stride phase, and uses server-confirmed attack timing. No mesh animation is active.

The PNGs are unmodified generation outputs. Atlas metadata, stable per-row scale/foot anchors and SHA-256 checksums are recorded in `manifest.json`. `python3 tools/register_rpg_sprites.py` remeasures the anchors without changing PNG pixels (requires Pillow, NumPy and SciPy). Source pose assets and per-artist attribution are in [LPC credits](../lpc/CREDITS.txt), and the game provides an Art Credits dialog. The redrawn derivatives are distributed under OGA-BY 3.0: https://static.opengameart.org/OGA-BY-3.0.txt. Original painted designs remain in `assets/animations/`.
