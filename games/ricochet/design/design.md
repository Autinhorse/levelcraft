
📄 Ricochet: Overall Design Document
1. Main Menu
The Main Menu features the game title and two primary buttons:

Play Game: Enter the level selection or start the campaign.

Make Levels: Enter the integrated Level Editor.

2. Gameplay Mechanics
The game is a 2D platformer-style world.

Character: The hero is a 1×1 square hitbox. 1 tile = 48×48 pixels.

Controls: Arrow Keys (Up, Down, Left, Right) for launches; Space for jump.

State Management: The hero can only receive inputs when stationary on the ground (or moving passively on a conveyor belt).

Movement Rules:

Left / Right: The hero first ascends 1 tile vertically, then moves horizontally in the chosen direction.

Up: The hero flies directly upwards.

Down (on the ground): no effect in v1 (reserved for future use).

Space (Jump): The hero performs a vertical jump of 2 tiles in place. **Input is accepted during the entire jump arc** (both ascent and descent) — pressing any arrow key while airborne launches the hero in that direction from the current mid-air position. With no input, the jump rises 2 tiles, pauses, and falls naturally. Once a directional launch is triggered (from ground or mid-jump), the hero becomes non-controllable until an obstacle is hit.

Execution: Once a directional launch (L/R/Up/Down-from-jump) starts, the hero becomes non-controllable until an obstacle is hit.

Obstacle Interaction:

Lethal Obstacles: Character dies immediately.

Special Obstacles: Triggers specific abilities (e.g., Adhesion, Teleportation).

Standard Obstacles:

If flying horizontally or upwards: The hero hits the wall, pauses briefly, and then starts to fall. If it's a horizontal hit, the hero rebounds by 1 tile before falling.

If moving downwards: The hero stops and lands on the obstacle.

Recovery: Control is returned to the player once the hero has landed or rebounded.

3. Level & Viewport Logic
Viewport: 25×20 tiles = 1200×960 pixels. When launched directly via "Play Game" the OS window is exactly 1200×960. When test-played from inside the editor, the same 1200×960 viewport renders inside the editor's left edit area; the editor's full window stays 1600×960.

Pages: A level consists of multiple "Pages." Each page can have custom dimensions.

Centering: If a Page is smaller than the viewport, it is centered with a blank fill.

Scrolling: If a Page is larger than the viewport, the camera follows the hero. The camera stops at the map boundaries to prevent the "void" from entering the viewport.

Core Elements:

Walls: Standard collision blocks. Map boundaries are treated as walls by default.

Spawn Point: One per Page.

Exit Point: One per Level.

Teleports: Inter-page portals. These contain a parameter defining the target Page ID.

Data Serialization: Level data is stored in JSON format.

Game Flow: Players start at Page 0. Reaching a teleport triggers a quick fade-to-black and transitions the player to the target Page's spawn point.

4. Game Parameters (Default Constants)
Tile size: 48×48 pixels.

Flight Speed: 5 tiles/second.

Rebound Distance: 1 tile.

Jump Height (Space, vertical): 2 tiles.

Gravity (g): 10 tiles/sec².

Terminal Velocity: Matches the flight speed (5 tiles/second).

5. Level Editor
The editor provides a full-featured suite for creation and management.

Level Management: List, Create, and Delete levels.

New levels require a name and are assigned a unique ID. **The ID is stored as a string in the level data file.** Locally generated IDs are 6-digit numeric strings starting at "100000"; once the game is hosted online, IDs will be alphanumeric short strings (e.g. "aB3xK9") issued by the backend. The game and editor treat the ID as an opaque string and do not assume any particular format.

UI Layout: 1600x960 total resolution.

Edit Area: 1200x960 (Left).

Toolbar: 400x960 (Right).

Canvas Logic:

Edit area: 25×20 tiles at 48 px/tile = 1200×960 pixels (matches the in-game viewport exactly). Maximum Page size: 64×64 tiles.

Auto-Sizing: The editor automatically calculates the final Page dimensions based on the furthest placed elements upon saving.

Navigation: Right-click to drag the map. Double-click (Left) to toggle between "Fit-to-Screen" (View Only) and "1:1 Zoom" (Edit Mode).

Toolbar Controls:

Page Navigation: Prev/Next page (with auto-save).

Page Management: Create new (highest index) or Delete current (with confirmation).

Clean-up Logic: Deleting a page automatically removes any teleportation points pointing to it and re-indexes subsequent pages.

Playtest Mode: Toggle to instantly test the current page.

Element Palette: Status-based icons for Walls, Teleports (requires target input), Spawn Points (max 1 per page), and Exit Points (max 1 per level).