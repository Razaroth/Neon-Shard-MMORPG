# Kairo Exchange / Concourse 09

The active environment has two connected, authored cyberpunk interiors. Characters occupy a connected floor surrounded by walls, recessed counters, doors, columns and foreground railings. The earlier repeating rooftop layouts remain in the screenshot history and are no longer used by the active renderer.

## Room construction

`assets/interiors/kairo-concourse.png` is an original generated cutaway room painting. The renderer draws the continuous architecture and floor, then dynamic characters, enemies and the relay kiosk. Tightly registered column silhouettes are composited at their correct depth; foreground railings sit in front of the actors. A column partially fades over the local character when it occludes them. Characters render at 164.4 pixels tall (20% larger than the previous 137-pixel presentation) to better match doors, workbenches and machinery. Foot anchors stay fixed; shadows and selection/attack indicators scale with the sprites, while health bars and labels sit above their heads. Elliptical foot shadows and restrained tinting ground the sprites on the painted floor.

The room has shared lighting, aligned floor tiles, wall recesses and fixtures at a consistent scale. It uses pre-rendered 2D artwork and baked lighting, not 3D geometry or a collection of full-building sprites. F8 toggles added interior dust and subtle actor light pools; it cannot remove lighting painted into the room artwork.

The camera follows the character within the room while clamping to the artwork edges. It favors showing the architecture above the player. There is no outdoor rain inside the hall. The HUD sits low in the frame to keep the surrounding architecture visible.

## Geometry and gameplay

`scripts/city_layout.gd` registers a walkable floor polygon and two support-column footprints against the 1536×1024 artwork. The client and dedicated server share the same world-to-art projection. Only coordinate data is needed by the server; it does not load the room painting.

Movement, attack sightlines and navigation use that geometry. Actors cannot cross the room walls or column plinths. Drones route around the supports. Older saved positions outside the room or inside a column are moved to a nearby valid floor position; class, health, items and mission progress remain unchanged.

The marked upper-right concourse doorway leads to the Maintenance Bay; its upper-left doorway returns to the concourse. Approach and press E. The bay uses its own original painting (`assets/interiors/maintenance-bay.png`), floor polygon, support footprint, navigation grid and drone simulation. Other painted doors and shops remain environmental set dressing.

The server validates doorway range, sightline and cooldown, then chooses the destination. Room changes preserve health, class, resources and contract progress, save immediately and briefly fade the view. Snapshots and combat are isolated by room. Arrival protection lasts two seconds and ends immediately when attacking. Full eight-direction sprite animation, crowds and a connected larger city remain future work.

## Class profiles

| Class | Playstyle | Health | Run speed | Reach | Damage | Attack interval |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Vanguard | Armored frontline / breach cannon | 150 | 125 | 105 | 30 | 0.65 s |
| Cipher | Hacking fantasy / neural pulse | 85 | 150 | 230 | 15 | 0.50 s |
| Ronin | Mobile duelist / arc blade | 100 | 180 | 85 | 20 | 0.30 s |
| Ghost | Precision marksman / rail carbine | 80 | 170 | 280 | 35 | 0.90 s |
| Machinist | Engineering fantasy / induction rig | 110 | 145 | 170 | 20 | 0.45 s |

Speed and reach use world units. These are initial balance values, enforced by the server. Distinct stats, portraits and animated sprites are implemented; skill trees, stealth, hacking mechanics and deployable companions are not. Five character slots per identity/server retain their original class and progression.

## Validation and previews

`tests/city_routes.gd` checks the authored floor, column collision, paths around supports, enemy pursuit, blocked attacks, saved-position migration and camera bounds. The multiplayer integration test exercises movement, the full contract, class slots and persistence across server restarts inside the rooms, including travel, room isolation, combat and saved-room restoration.

The visual fixture clicks all five class buttons, checks connection controls fit, and renders a staged co-op party, counter view, doorway view and a player behind a column. These are actual Godot renders, not live multiplayer captures or hardware performance benchmarks.

With a display available, regenerate them after importing the project:

```sh
./tools/godot.sh --audio-driver Dummy --script tests/visual_capture.gd -- --capture-dir /tmp/neon-shard-captures
```

Active generated art assets are the five `assets/animations/*.png` sheets, both continuous room paintings, `assets/portraits/characters-atlas.png`, and the drone/kiosk regions of `assets/city/props-atlas.png`. Earlier building and vector assets are retained but not loaded by the current gameplay renderer.

![Playable concourse](screenshots/interior.png)

## Sprite animation pass

Each class has a transparent 1536×1024 sheet with six columns and four rows: idle, walk, run, attack. The renderer selects rectangular regions without allocating per-frame textures. Texture sheets are cached once per client; the headless server does not load them. A common foot anchor retains floor registration at the current character scale. Attack cells trim their horizontal outer band to avoid adjacent-frame effects bleeding into the current pose.

Idle plays at 5 fps, walking at 9 fps and running at 13 fps. Attack duration is capped at 0.5 seconds and 90% of the class cooldown, so the Ronin's fast strikes complete before the next attempt. The server advances an attack serial and sends its age; clients play each attempt once, including misses. Movement state uses actual displacement after wall collision; stale input and doorway travel clear movement. Shift selects the existing class run speed; normal walking is 65% of it. Facing follows projected movement or the server's attack target and persists when stopped.

This is a first pass of generated six-frame cycles with mirrored left/right views, not full eight-direction artwork. Diagonal and vertical movement select the nearest horizontal facing. Frame consistency and foot contact still need hand polish; hit, death and equipment-specific animations are not implemented. Animation frame rates are presentation rates, not measured game performance.

`tests/animation_rules.gd` checks clip transitions, speeds, retained facing, wall blocking, attack completion and stale-input handling for all five classes. `tests/animation_capture.gd` renders the staged ten-second [animation reel](screenshots/animations.gif); real ENet tests separately exercise walk/run snapshots, combat, travel and persistence.
