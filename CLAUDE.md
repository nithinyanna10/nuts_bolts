# Where's That Screw?

Stylized low-poly 3D first-person game. Godot 4, GDScript, Jolt physics, Forward+ renderer, Windows target.

## Scope
- **Milestone 1 ONLY:** first-person warehouse, thousands of instanced screws, hand pickup, one magnet upgrade, one rare golden bolt, money counter, satisfying feedback.
- Refuse to build anything outside this unless the user asks.

## Architecture
- Modular code: one responsibility per script.
- Signals over direct references.
- Autoload `EventBus` for game-wide events; autoload `Economy` for money.

## Code rules
- Static typing in all GDScript.
- Screws render via `MultiMeshInstance3D`. Never one node per screw. Promote to `RigidBody3D` only for a handful of nearby interactive objects.
- All tunables (spawn counts, magnet radius, prices, rarity rates) live in exported vars or a Resource, never hardcoded in logic.

## Git
- Never add Co-Authored-By or any Claude/Anthropic attribution to commits.
- Commit after each working step with a short, plain message.

## Layout
- `scenes/{main,player,warehouse,screws,equipment,ui}`
- `scripts/{player,inventory,collection,economy,upgrades,procedural,ui}`
- `assets/{audio,materials,meshes}`
