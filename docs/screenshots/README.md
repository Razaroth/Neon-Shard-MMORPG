# Neon Shard · Kairo Exchange interior

The active area is now **one continuous cutaway transit hall**, with characters walking inside connected architecture. It replaces the repeated full-building layout with an authored floor, surrounding walls, recessed counters, structural columns, and foreground railings.

These are actual Godot renders with dynamic game actors. They are staged visual captures; real multiplayer combat and persistence were tested separately.

## Inside the concourse

![Playable transit hall](interior.png)

[Open the full-size interior image](interior.png) · [Added effects reduced](interior-low.png)

## Approaching the counter

![Character near the counter](interior-counter.png)

[Open counter view](interior-counter.png)

## Connected room architecture

![Doorway and transit windows](interior-doorway.png)

[Open doorway view](interior-doorway.png)

## Foreground depth

![Character behind a support column](interior-occlusion.png)

[Open column occlusion view](interior-occlusion.png)

Column footprints block movement and attacks. Their silhouettes are depth sorted with actors and partially fade over the local player when needed. The room camera stays within the artwork boundaries. Characters have foot shadows and move on the registered floor, rather than across an aerial view of roofs.

## Class selection

![Character selection](character-selection.png)

[Vanguard](class-vanguard.png) · [Cipher](class-cipher.png) · [Ronin](class-ronin.png) · [Ghost](class-ghost.png) · [Machinist](class-machinist.png)

## Previous layouts

[Previous repeated rooftop layout](city-rooftop-layout.png) · [Earlier open layout](city-open-layout.png) · [Original city](city-before.png)

## Current scope

This is one playable interior, using an original generated room painting, registered collision geometry, and dynamic characters/enemies. It is not 3D geometry or a completed connected city. Shops and doorways are environmental set dressing until interactions and room transitions are added. Directional sprite animation and crowds remain future work.

Room collision, navigation around columns, enemy pursuit, blocked attacks, old-save relocation and camera bounds passed their checks. The real two-client integration test also passed movement, combat, mission rewards, character-slot persistence and server restart restoration.

The screenshots are not a hardware performance benchmark. This preview branch publishes the gallery; development source remains in the working environment.
