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

## Continuous character motion

The six independently generated poses were not temporally consistent: silhouettes changed, foot contacts jumped, and Cipher's attack introduced an unrelated rifle. Vanguard, Cipher, Ghost and Machinist now use the first idle cell of their sheets as stable skins. Ronin uses `assets/animations/ronin-layered.png`, with a weapon-free body and a separate rigid katana layer attached to the deformed hand anchor. The unused generated cells remain in the source artwork for reference, but no longer drive animation.

`scripts/character_rig.gd` deforms a connected 493-vertex mesh. Each class has registered hip, knee and sole anchors; a two-bone inverse-kinematics solve rotates each thigh and shin without changing bone lengths. Unreachable foot targets are clamped to the leg’s reach. Boot orientation stays level while shoulders counter-swing, hips lower into running and the coat follows the stride. Weapon weights preserve the firearm silhouettes. Ronin’s separate katana rotates rigidly around the hand so leg movement cannot bend the blade. All five classes retain the same appearance throughout movement. Profiles give Vanguard a heavier stride/recoil, Ronin longer strides and a sharper lunge, Ghost restrained breathing/recoil, and Cipher/Machinist hand motions and energy feedback that preserve their devices.

`scripts/character_animation.gd` advances gait by actual displayed travel distance, retains phase when switching between walking and running, and smoothly blends movement, lean, breathing and coat follow-through. A foot spends 60% of its cycle in stance. Its target is locked in world space during contact, including acceleration, and recovery starts from the actual toe-off point. Hermite tangents match stance velocity at touchdown. Stopping retains the foot’s horizontal placement while an airborne boot settles; resuming an interrupted swing begins from that settled position. Walking uses a longer cycle than the earlier version, reducing hurried shuffling. These are planar foot targets with reach limits, not terrain-aware 3D IK; turns, painted joint areas and extreme poses still need art and rig refinement.

Server movement eases into the existing class speed over roughly a tenth of a second, brakes quickly, and stops stale inputs immediately. Walking remains 65% of run speed. Collision determines actual velocity, so pushing into a wall cannot cycle feet. Facing has hysteresis and an eased mirrored-view transition. The server's attack serial/age controls recoil and energy/blade feedback without changing damage, cooldowns or rewards. Recoil builds from rest instead of jumping to its maximum on the first frame. Ronin’s rigid blade uses a small anticipation, a fast strike and a slower recovery; its trail shares the same hand transform and blade rotation.

Meshes and textures are reused per actor/class. Skin weights are cached, and joint/shoulder transforms are calculated once per pose rather than once per vertex. The server never loads the visual skins. The dynamic mesh is rebuilt on the client; large populations and target-device performance have not been profiled. The software-rendered preview is evidence of playback, not a 60 fps hardware benchmark.

This remains a **procedural 2D mesh deformation** approach with mirrored views. It does not provide full eight-direction artwork, a true articulated 3D skeleton, motion capture, or AAA release-quality animation. Achieving that quality requires authored layered or skeletal characters with controlled joints, complete directional cycles, terrain-aware foot placement, authored transition animations and an art review pass. Hit/death/equipment variants remain future work.

`tests/animation_rules.gd` checks acceleration, phase continuity, class profiles, eased turns, world-space stance targets, rigid bone lengths under reachable and unreachable targets, stop placement, sword recovery, continuous loop boundaries, frame-rate independence, stale input and server attack cancellation. `tests/animation_capture.gd` uses real movement code to capture all five classes walking, running, stopping, attacking and reversing direction at 30 capture frames per second. Real ENet tests separately exercise combat, travel and persistence.
