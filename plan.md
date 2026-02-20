# Project Status Document

# 1. Project Overview

- **Vision**: Flow-based RTS where hundreds of autonomous units naturally form frontlines and flank based on density. Player manages flow, not individual units.
- **Tech Stack**: Godot 4.3, GDScript, Forward+ Renderer, Native deployment (Linux/Windows)
- **Development Approach**:
    - Claude Code for implementation, planning, and architecture
    - Direct file editing and testing in the codebase
    - This plan.md file for documentation and status tracking

# 2. Current Phase Status

- **Phase 1 (Engine Core)**: COMPLETE
- **Phase 2 (Logic Core)**: COMPLETE
- **Phase 3 (Unit Movement)**: COMPLETE
- **Phase 4 (Combat System)**: COMPLETE
- **Phase 5 (Economy & Structures)**: COMPLETE
- **Phase 6 (Builder Movement Refactoring)**: COMPLETE
- **Phase 7 (UI & Structure Info Panel)**: IN PROGRESS
- **Phase 8 (Map & AI — Required Before Publishing)**: PENDING

# 3. Completed Systems

## 3.1. Map Generation (Phase 1)

- Hexagonal grid procedural generation using Odd-R offset coordinates
- Physics-based tile interaction via `StaticBody3D` with trimesh collision
- Support for multiple tile types (grass, dirt, stone, water)
- Kenney assets with 0.577 scaling factor
- `MapGenerator.gd` creates visual mesh instances
- `Grid.gd` maintains logical tile data structure

## 3.2. Camera System (Phase 1)

- RTS camera with pan (WASD/arrows), edge scrolling, middle-click drag
- Mouse wheel zoom with height clamping (1-50 units)
- Raycast-based tile selection using `PhysicsRayQueryParameters3D`
- Emits `hex_clicked` signal with `Tile` object
- Click detection works across multiple tile heights
- Strategic zoom: seamless transition to high-altitude overview for broad map awareness

## 3.3. Grid System (Phase 2)

- `Tile` class with grid coordinates, world position, walkability, cost
- Neighbor connectivity using Odd-R offset calculations
- Node-to-coordinate reverse lookup for raycast results
- Coordinate validation and bounds checking
- Central storage for hex geometry constants (`HEX_SCALE`, `X_SPACING`, `Z_SPACING`)

## 3.4. Flow Field System (Phase 2)

- Dijkstra-based flow field calculation for pathfinding
- Multi-source target support with priority costs
- Stores flow data separately from Tiles (supports multiple players)
- Per-player flow field instances
- Query interface: `get_flow_cost()`, `get_flow_direction()`

## 3.5. Player System (Phase 2)

- `Player` class owns units array, flow field, resources, target
- Unit spawning with correct hex-to-world coordinate conversion
- Flow field calculation triggered by player
- Support for multiple players with separate flow fields

## 3.6. Unit System (Phase 3)

- `Unit` class with proper constructor initialization
- MagicaVoxel mesh rendering with hex scaling
- Positioned via hex coordinates with Odd-R offset
- Flow field-based pathfinding implementation
- Periodic movement checks (0.5s timer for idle units)
- Formation slot claiming and release system
- Multi-tile movement with proper tile transitions
- Combat detection and movement stopping
- Health system with 3D health bars
- Attack system with cooldown and ranged targeting
- Dynamic height correction via raycasting
- Smooth rotation to face movement direction
- Unit death and cleanup handling
- Muzzle flash visual effects using `OmniLight3D`

## 3.7. Combat System (Phase 4)

- Range-based enemy detection (`attack_range` from `game_data`)
- Closest enemy targeting with distance calculations
- Combat engagement prevents movement
- In-combat flag for density cost calculations
- Muzzle flash effects on attack
- Tested with 250+ units in active combat
- Flanking behavior via density-based flow costs
- Multi-unit combat scenarios validated

## 3.8. Performance Characteristics

- Successfully tested with 250+ units at stable framerates
- Automatic unit spawning system (1 unit per second per player)
- No time-slicing required at current scale
- Game clock tracking (MM:SS format)
- Periodic flow field recalculation (2s intervals)
- Unit count tracking and reporting
- Range-based combat detection scales well

## 3.9. Economy System (Phase 5 - Expanded)

- Structure placement system with preview and validation
- Resource tracking and display UI
- Passive income from bases and mines
- Structure production timers for units
- Build menu with cost display and affordability checks
- Improvement placement restrictions (adjacent to bases only)
- Multiple structure types (base, drone_factory, mine, cannon, etc.)
- Per-player structure ownership and management
- Production control system with per-structure toggles for resource generation and unit production
- Structure selection with visual feedback (yellow highlight with emission)
- Multi-selection support with Ctrl+click
- "Select All of Type" functionality for batch control
- Structure attack system (cannon, artillery) - auto-attacks closest enemy tile, damages all units on tile

- Implement army unit cost.

- Separate builder list on tiles (currently using formations slots). Builders should be targetable and collide with enemies, but pass through full formations and 

## 3.10. Builder Unit System

- Builder units spawned from base structures at regular intervals
- Autonomous builder pathfinding using flow fields toward construction targets
- Builder assignment to construction queue (structures and roads)
- Progressive resource delivery and health restoration during construction
- Automatic despawn when construction is complete
- Multiple builders can work on same structure simultaneously
- Builders move to tile center only (no formation offsets), tracked in `Tile.builder_occupants` separate from `occupied_slots`
- Builders pass freely through friendly structures and friendly units; blocked only by enemy military units
- Builders never stop mid-path — they always keep moving until arrival or enemy blockage

## 3.11. Forward Structure Deployment

- Structures can be built far from bases via construction queues
- Builders autonomously navigate to remote construction sites
- Remote structures have same functionality as base-adjacent structures
- Road networks enable optimized builder pathfinding to distant sites
- Construction progresses as resources are delivered by builders

## 3.12. Victory & Defeat Conditions

- **Victory**: Destroy all enemy bases (only completed bases count)
- **Defeat**: All player bases destroyed
- Game state management with three states: PLAYING, VICTORY, DEFEAT
- Game pause on victory/defeat (all timers paused)
- Game over overlay with appropriate title and message
- Victory screen: Gold text "VICTORY!" with enemy destruction message
- Defeat screen: Red text "DEFEAT" with base destruction message
- Restart and quit functionality to manage game lifecycle
- Input blocking during game over state
- Base counting logic that correctly excludes under-construction bases
- Signal system for structure destruction detection and state checking

## 3.13. Debug Visualization

- Flow field arrow visualization with color gradients
- Per-player color schemes (P0: green/yellow/red, P1: blue/cyan/magenta)
- Automatic cycling between player flow fields every 2 seconds
- Click marker shows selected tile center
- Both systems marked as temporary debug code

# 4. Architecture Quality

## 4.1. Design Principles Achieved

- **Single Responsibility**: Each class has clear, focused purpose
- **Signal Down, Call Up**: Proper Godot hierarchy (siblings signal, children called)
- **Data-Driven**: Tile properties, flow fields, unit stats stored in `game_data.gd`
- **Modular**: Clean interfaces, minimal coupling between systems
- **Validated**: Error handling with descriptive messages throughout

## 4.2. Key Architectural Decisions

- Flow fields stored separately from Tiles (multiplayer support)
- Players own their flow fields and units
- Grid owns hex geometry constants (single source of truth)
- `Game.gd` coordinates high-level systems
- `map.gd` minimal coordinator for map generation only
- Forward+ renderer (abandoned web deployment for performance)
- All game configuration centralized in `data/game_data.gd`

## 4.3. Technical Debt Resolved

- Merged duplicate `Player` classes
- Moved game logic from `map.gd` to `Game.gd`
- Simplified `FlowFieldVisualizer` to single-method interface
- Fixed `Unit` initialization to use proper constructor
- Consolidated duplicate hex constants into `Grid.gd`
- Added validation and error handling throughout
- Fixed click system to emit `Tile` objects
- Centralized all unit stats in `game_data.gd`

# 5. File Structure

## 5.1. Core Systems

```
src/core/
├── Grid.gd          - Logical grid, neighbor mapping, hex constants
├── Tile.gd          - Tile data (coords, world_pos, walkable, cost, neighbors)
├── FlowField.gd     - Flow field calculation and queries
├── MapGenerator.gd  - Visual hex grid generation
├── map.gd           - Map coordinator (minimal)
├── Structure.gd     - Structure entity with mesh, health, production
└── Unit.gd          - Unit entity with mesh rendering, combat, movement
```

## 5.2. Game Systems

```
src/
├── Game.gd                 - Main game coordinator, player management
├── Player.gd               - Player entity with units, structures, flow field
├── AIPlayer.gd             - AI player with automatic decision making
├── RTSCamera.gd            - Camera control and tile selection
├── FlowFieldVisualizer.gd  - Debug: Flow field arrow rendering
├── HealthBar3D.gd          - 3D health bar rendering
├── ResourceDisplay.gd      - UI: Resource counter
├── BuildMenu.gd            - UI: Structure building buttons
└── StructurePlacer.gd      - Structure placement preview and validation
```

## 5.3. Data Configuration

```
data/
├── game_data.gd            - Centralized game configuration
│   ├── UNIT_TYPES          - Unit definitions (infantry, tank, scout)
│   ├── STRUCTURE_TYPES     - Structure definitions (base, drone_factory)
│   ├── TILES               - Tile type definitions
│   ├── PLAYER_CONFIGS      - Player setup
│   └── Map constants
└── game_config.gd          - Gameplay tuning constants
```

## 5.4. Scene Structure

```
game.tscn
├── Game (Node3D)
│   ├── Camera3D (RTSCamera.gd)
│   ├── Map (map.gd)
│   │   ├── Grid (Grid.gd)
│   │   ├── MapGenerator (MapGenerator.gd)
│   │   └── FlowVisualizer (FlowFieldVisualizer.gd)
│   ├── StructurePlacer (StructurePlacer.gd)
│   ├── CanvasLayer
│   │   ├── ResourceDisplay
│   │   └── BuildMenu
│   ├── Player0 (Player.gd) - added at runtime
│   └── Player1 (AIPlayer.gd) - added at runtime
```

# 6. Next Development Steps

## 6.1. Phase 5: Economy & Structures (COMPLETE)

- **Goal**: Strategic resource-based gameplay with buildings.
- **Completed**: Resources, passive income, structure placement, build menu UI, unit production, improvement placement restrictions, production pause/resume toggles, visual selection feedback, builder units, forward structure deployment rules, victory/defeat conditions

## 6.2. Phase 6: Builder Movement Architecture Refactoring (COMPLETE)

- **Goal**: Separate builder movement mechanics from military unit formation system
- **Solution**: Builders now use a dedicated `builder_occupants` array on each `Tile`, fully separate from `occupied_slots`
- **Changes**:
  - `Tile.gd`: Added `builder_occupants: Array`, `register_builder()`, `unregister_builder()`
  - `Builder.gd`: Removed `formation_slot` and `formation_position`; rewrote `_advance_to_next_waypoint()` to move to tile center, check `has_enemy_units()` only, and never wait on slots
  - Military density costs and `has_enemy_units()` are unaffected by builders

## 6.3. Phase 7: User Interface & Control (Future)

- Additional UI polish and player feedback
- Advanced selection tools
- Upgrade menu
- Additional game state indicators
- **Structure info panel**: When a structure is selected, display a dedicated info panel showing:
  - A small camera view or sprite of the structure
  - Structure name and type
  - Unit production cost and production time (e.g. "100 resources / 5s = 20/sec") for factories
  - Current health and status
  - This applies to all structure types, not just factories

## 6.4. Phase 8: Map & AI (Required Before Publishing)

- **Map generator improvements**: More varied and interesting procedural maps — varied terrain distribution, choke points, resource placement strategy, visual variety
- **AI improvements**: More capable and varied AI behaviors — better build order decisions, strategic structure placement, adaptive responses to player actions

# 7. Known Issues and Limitations

## 7.1. Current Limitations

- Hardcoded 2-player setup for testing
- Limited UI (resource display, build menu, and production control)
- No save/load system

## 7.2. Performance Status

- **Target**: 500+ units at native framerate
- **Tested**: 250+ units stable performance
- **Strategy**: No time-slicing needed at current scale
- **Current**: Godot handles physics and rendering efficiently
- Combat range detection scales well
- **Note**: Performance headroom available for structures and additional features

# 8. Testing Status

## 8.1. Manual Testing Completed

- Tile click detection at multiple heights
- Flow field calculation for both players
- Flow field visualization cycling
- Unit spawning at correct coordinates
- Camera controls (pan, zoom, edge scroll, drag)
- Unit movement along flow fields
- Formation slot claiming and positioning
- Combat detection and engagement
- Unit death and cleanup
- Multi-unit pathfinding (250+ units)
- Height correction on uneven terrain
- Attack system with cooldown
- Health bar display and updates
- Ranged combat (`attack_range` parameter)
- Muzzle flash visual effects
- Flanking behavior with density costs
- Large-scale combat scenarios
- Structure placement with preview
- Resource display updates
- Basic AI player behavior

## 8.2. Edge Cases Validated

- Invalid coordinate handling with error messages
- Null reference checks throughout
- Water tiles marked unwalkable with `INF` cost
- Odd-R offset calculations for odd/even rows
- Full formation slot handling
- Enemy detection across tile boundaries
- Unit cleanup on death (slot release, array removal)
- Range-based targeting with multiple enemies
- Combat state transitions

## 8.3. Performance Testing

- Stable performance with 250+ active units
- Automatic spawning system functional
- Flow field recalculation under load (2s intervals)
- Physics processing scales well
- No time-slicing required at current scale
- Range-based combat detection performance validated

# 9. Key Technical Details Reference

## 9.1. Hex Grid Math (Odd-R Offset, Pointy-Top)

- `HEX_SCALE = 0.6`
- `X_SPACING = 1.732 × 0.57735 ≈ 1.0`
- `Z_SPACING = 1.5 × 0.57735 ≈ 0.866`
- Odd rows: offset by `X_SPACING/2`

## 9.2. Node Structure Pattern

```
StaticBody3D (Hex_x_z) - collision and identification
└── MeshInstance3D - visual mesh with trimesh collision
```

## 9.3. Flow Field Data Structure

```
flow_data: {
    Vector2i(x,z): {
        cost: float,
        direction: Vector2i
    }
}
```

## 9.4. Game Data Structure Pattern

All configurable game content follows this pattern in `data/game_data.gd`:

```gdscript
const ENTITY_TYPES = {
    "entity_name": {
        "display_name": "Human Readable Name",
        "mesh_path": "res://path/to/mesh.obj",
        "property1": value1,
        "property2": value2,
        ...
    }
}
```

Applied to: `UNIT_TYPES`, `STRUCTURE_TYPES`, `TILES`

# 10. Development Workflow

## 10.1. Making Changes

1. Request feature or change from Claude Code
2. Claude Code implements directly in the codebase
3. Test in Godot
4. Iterate with Claude Code if needed
5. Update status document when complete

## 10.2. Working with Claude Code

Claude Code can:

- Read and edit files directly in the codebase
- Run bash commands and tests
- Search for code patterns and files
- Implement features end-to-end
- Debug issues by reading error messages
- Update documentation and status

Best practices:

- Be specific about what you want changed
- Mention Godot version (4.3) for context
- Share error messages for debugging
- Describe expected vs actual behavior

## 10.3. Data-Driven Development Pattern

- All new game content starts in `game_data.gd`
- Define entity types with all properties as dictionaries
- Create generic classes that read from config dictionaries
- Use type strings to differentiate behavior when needed
- Keep game logic separate from data definitions
