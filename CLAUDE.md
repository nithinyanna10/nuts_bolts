# Where's That Screw?

Stylized low-poly 3D first-person game. Godot 4, GDScript, Jolt physics, Forward+ renderer, Windows target.

## Game direction (locked)
"Where's That Screw?" is a first-person, skill-based hidden-object game.
- **Core mode:** short rounds. A customer order specifies one exact screw/bolt/nut/washer. Exactly one match exists in a pile of similar distractors. The player scans the pile, crouches to get close, picks up candidates into their hand, inspects them (rotate with mouse, zoomed camera), then either submits or tosses them aside. Tossing aside is how you dig. Wrong submissions cost time or score.
- **No money from picking things up, ever.** Money comes only from completing rounds.
- **Secondary mode (later):** "Impossible Order", one legendary bolt in a million-object pile.
- Refuse to build anything outside this direction unless the user asks.

## Design rules
- Objects are stylized and oversized (a bolt about hand length) so differences are readable in first person.
- Crouch/lean-in brings the camera close to the pile.
- The generator guarantees exactly one match, and every distractor differs from the target in at least one checkable property.
- The target is never unreachable by digging.
- Magnets and other upgrades are future search tools, not money machines. The current magnet and shop are disabled.

## Architecture
- Modular code: one responsibility per script.
- Signals over direct references.
- Autoload `EventBus` for game-wide events; autoload `Economy` for money.

## Code rules
- Static typing in all GDScript.
- Pile objects render via `MultiMeshInstance3D`, one MultiMesh per object variant. Never one node per object. Only the hovered/inspected object is promoted to a real node.
- All tunables (spawn counts, difficulty settings, payouts, penalties) live in exported vars or a Resource, never hardcoded in logic.

## Git
- Never add Co-Authored-By or any Claude/Anthropic attribution to commits.
- Commit after each working step with a short, plain message.

## Layout
- `scenes/{main,player,warehouse,screws,equipment,ui}`
- `scripts/{player,inventory,collection,economy,upgrades,procedural,ui}`
- `assets/{audio,materials,meshes}`
