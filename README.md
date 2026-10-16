# Neon Shard

An original cyberpunk online game built with Godot 4.6.3. Communities host their own dedicated persistent worlds. The current playable areas are **Kairo Exchange** and a connected **Maintenance Bay**, two enclosed cutaway interiors with authored floors, walls, machinery and support columns. This is an early multiplayer prototype, not a finished MMORPG.

## Play on Windows (64-bit)

1. [Download the game source ZIP](https://github.com/Razaroth/Neon-Shard-MMORPG/archive/refs/heads/main.zip), then choose **Extract All**. Run from the extracted folder, not inside the ZIP.
2. Double-click **Play-Windows.cmd**. The first run downloads Godot 4.6.3 from its official GitHub release, verifies the pinned SHA-512 checksum, and imports the game assets. Internet is needed for that first download. No editor installation or administrator account is required.
3. Choose a class and character slot, leave the address at **127.0.0.1**, then click **CONNECT**. Keep the launcher open while playing; closing the game ends its local server.

If Windows shows a downloaded-file prompt, review the scripts before allowing this unsigned prototype to run. The launcher uses PowerShell for this process only; it does not change your saved execution policy. A managed computer may restrict scripts; the manual Godot steps below remain available.

Local server characters are saved under `%LOCALAPPDATA%\NeonShard\world`; the runtime and launcher logs also live under `%LOCALAPPDATA%\NeonShard`. Keep your Godot `user://identity.cfg` as well to retain access to the same character. Do not run two local launchers simultaneously. Closing the launcher or forcibly stopping the server can lose recent unsaved progress.

This is a source-based playable prototype, not an exported Windows installer. The server/client gameplay is tested on Linux; the Windows launcher has not been run on a Windows machine yet. Local play needs no router setup or public server.

## Run manually / develop

Install Godot **4.6.3 standard**; .NET is unnecessary. Open `project.godot` in Godot. From the checkout, start a separate server:

```sh
godot4 --headless --path . -- --server --port 2456
```

Run the project, choose a class and character slot, and connect to `127.0.0.1`.

- WASD / arrows: walk. Hold Shift to run (uses the existing class speed; walking is 65% of that).
- Hold Space: attack the closest visible drone in your class's range.
- E: travel at a marked doorway, or use the concourse relay after defeating three drones, collecting the one-time 100-credit contract reward.
- F8: toggle added dust and subtle actor light pools.

On Windows, use the Godot console executable in place of `godot4`. Servers need no editor or display. On Linux, the helper supplies writable local data/cache paths:

```sh
./tools/godot.sh --headless -- --server --port 2456
./tools/godot.sh
```

Set `GODOT_BIN` if your executable has another name. See [hosting instructions](docs/HOSTING.md) for storage and network limitations.

## Characters and persistence

Vanguard, Cipher, Ronin, Ghost and Machinist have distinct server-enforced combat stats, portraits and animated in-game sprites. Each class uses a stable 2D skin with continuous mesh-based breathing, strides, coat follow-through and class-specific attack feedback. Movement accelerates and brakes smoothly; walk/run transitions retain gait phase and stride follows actual distance. Articulated leg joints preserve limb lengths, foot targets stay planted through stance, and stops settle without pulling boots back to the starting pose. Mirrored left/right facing eases through turns. Attack motion follows server-confirmed attempts and cannot change damage or cooldowns. This is a procedural 2D motion pass, not release-quality authored skeletal animation: full eight-direction turns, hit reactions, death clips and further rig polish remain future work. Each client identity has five independent slots per server. Existing slots restore their saved class; an unused slot lets you try a different class. Separate identities can be selected with `--identity-file /absolute/path/identity.cfg`.

The server saves class, room, health, position, scrap, credits and contract progress every five seconds, on observed disconnect, and on acknowledged leave. Travel and contract turn-in save immediately. Defeat returns you to a safe arrival point in your current room with full health; resources and progress are retained. Old positions outside the new room are moved onto a valid floor location without resetting the character. Older records with no class become Ronin in slot 1.

## Verification

Requires Godot 4.6.3 and Python 3:

```sh
./tools/godot.sh --headless --editor --import --quit
./tools/godot.sh --headless --script tests/combat_rules.gd
./tools/godot.sh --headless --script tests/class_rules.gd
./tools/godot.sh --headless --script tests/city_routes.gd
./tools/godot.sh --headless --script tests/travel_rules.gd
./tools/godot.sh --headless --script tests/animation_rules.gd
python3 tests/multiplayer_smoke.py
```

The rules check combat range/cadence, duplicate rewards, respawn, classes, room collision, pursuit around columns, sightlines and camera bounds. The real ENet integration test runs two clients, verifies movement and saves, completes the contract, restarts the server and checks character slots and progression. It also walks through both doorways, checks room isolation, fights in the maintenance bay, and verifies saved room, health and loot after a server restart. It uses isolated temporary data and cleans up its own processes. Local sockets must be permitted by the execution sandbox.

[Animation preview and interior screenshots](docs/screenshots/README.md) show staged Godot renders rather than live multiplayer. [Art and geometry notes](docs/VISUALS.md) explain the active room and limitations.

## Scope and next milestones

Implemented: dedicated server, persistent character slots, authoritative movement/combat, drone AI, loot counts, one contract, and two connected playable interiors with registered collision, foreground occlusion and room-specific enemies.

Next: secure authentication/access controls and backups; more rooms and district transitions; full eight-direction animation and hit/death reactions; equipment, more contracts and enemies; chat, parties and trading. Larger world simulation, interest management and population targets require profiling and load tests. Only two concurrent clients have been exercised; the 32-connection admission setting is not a supported capacity claim.

The current ENet identity protocol is unencrypted and intended for trusted private testing. Public hosting hardening is unfinished. The marked concourse/maintenance doorway works; shops and other painted doors remain environmental art. No paid infrastructure has been provisioned.
