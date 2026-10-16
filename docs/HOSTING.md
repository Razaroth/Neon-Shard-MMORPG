# Dedicated server prototype

## Start

From the project checkout, with Godot 4.6.3 standard installed:

```sh
godot4 --headless --path . -- --server --port 2456 --save-dir /absolute/path/to/neon-world
```

`SERVER_READY` confirms the UDP listener is bound. Confirm actual readiness by connecting a client and moving. For cloud development, `./tools/godot.sh` provides writable data/cache locations. Run clients from the same project revision as the server.

The host does not need to keep a game client open. For continuous operation, a future release will provide service/container packaging; currently run Godot under your preferred process supervisor. Use one process per world and separate save directories and UDP ports. Two servers must never write to the same save directory.

## Storage

Without `--save-dir`, Godot stores `world/characters.json` below its platform-specific `user://` directory. The Linux helper uses `.local/data/godot/app_userdata/Neon Shard/` inside the checkout unless XDG paths are already configured. `.local/` is ignored by Git. Prefer an explicit absolute save directory for hosting.

Back up `characters.json` while the server is stopped. To restore, stop the server, preserve the existing directory, then copy a known good backup into place. The file is written through a temporary file and rename. Invalid JSON causes startup to fail rather than overwrite the save. Writes are not a database transaction or a guarantee against disk/power failure. Five seconds of recent movement can be lost on abrupt termination. Backups and schema migrations are not automated yet.

The client identity file is a bearer credential: preserve it privately to keep access to your character. Losing it creates a new character; copying it grants access to that character. The server stores a hash of it, plus character slot/class, room, coordinates, health, resource counts, and contract progress. There is no password reset or account recovery yet.

## Network and access boundary

This prototype is for local development or a trusted private network. ENet traffic is not encrypted here, and there are no server passwords, bans, robust flood protection, or secure account authentication. Do not expose this version directly to the public Internet. Use a trusted VPN/private network for remote prototype sessions; encrypted transport and operator access controls are required before public hosting.

In a future public hosting release, direct connections require inbound **UDP 2456** (or the configured port), firewall permission, and usually router port forwarding. Carrier-grade NAT may require a provider with a reachable public address or a relay; a server browser alone cannot solve that. No automatic port forwarding or relay service is implemented.

The project uses an original setting and contains only placeholder visuals. The first drone combat contract is implemented. Item inventories, a player economy, additional missions, moderation tools, discovery, host-and-play UI, Docker images, and release binaries remain future work. Enemy state resets on restart; character health, loot, credits, and contract completion persist.


## Character slots and compatibility

The menu offers five slots for each client identity on each server. Slot 1 retains the original identity hash for compatibility. Older records without a class load as Ronin with their previous health and progress. New slots use separate server-side records; an existing character's class is never replaced by a connection request. Updated clients and servers must use the same project revision because the registration RPC and snapshots now include class/slot information.


## Enclosed-layout update

Older saved positions inside new room walls or columns are automatically projected to the nearest valid floor position when the character joins. Health, class, resources, and contract progress remain intact. Use matching client/server revisions because both depend on the same authored room geometry and attack sightline rules.


## Kairo Exchange interior

The concourse and maintenance bay are connected by marked doorways (approach and press E). Travel is server validated and saves room and position immediately. Records without a room default to the concourse; invalid positions are moved onto that room’s floor. Each room has isolated enemies and player snapshots; enemy state in both rooms resets on restart. Their floor polygons and column footprints are shared by the server and client. Characters saved in the earlier city layout are moved to a valid room floor position on join; class and progression are preserved. The dedicated server loads geometry data but does not load the room texture. Matching client/server revisions remain required.

## Animation and movement protocol

Use the same updated source on clients and server: movement RPCs now carry a run intent, and snapshots include actual velocity, moving/running state, facing and server attack serial/age. Existing class speeds are run speeds; walking uses 65% of those values. Character save format and progression remain compatible. The Windows local launcher starts both from the same checkout.

Movement now accelerates and brakes on the server. Keep clients and servers on the same revision; stale-input timeout and collision remain server-enforced. The continuous animation rig is client-side and does not change saved character data.
