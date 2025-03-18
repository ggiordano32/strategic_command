# Strategic Command

An open-source isometric RTS game combining the best elements of Command & Conquer: Red Alert 2 and Company of Heroes, built with the Godot Engine.

#### Claude Reasoning Experiment

This is an experiment in using Claude.ai 'Projects' with git integration to build a Real Time Strategy game.

## Game Concept

Strategic Command merges the isometric base-building of classic RTS games with the tactical squad-based gameplay and cover systems of modern strategy titles. The game focuses on strategic positioning, resource control, and asymmetric faction design.

### Key Features

- **Squad-based Tactical Combat** with cover mechanics and positioning advantages
- **Isometric Base Building** with strategic placement considerations
- **Resource Control Points** that generate resources over time
- **Asymmetric Factions** with unique units and playstyles
- **Multiplayer** 1-4 players up to 2v2 matches (Peer to Peer to start?)
- **Bot Support** simple AI for testing with advanced ai coming in a later phase
- **(Real Stretch) Destructible Environments** that changes battlefield dynamics

## Factions

### The Coalition
Western-inspired forces focusing on mobility, technology, and adaptability.

### The Collective
Eastern-inspired forces emphasizing strength in numbers, industrial efficiency, and defensive power.

### Roadmap
[Implementation Guide](IMPLEMENTATION_GUIDE.md)

## Technical Implementation

This game is being developed with Godot Engine 4.x, using GDScript for game logic.

## Getting Started

### Prerequisites
- Godot Engine 4.x

### Installation
1. Clone this repository
2. Open the project in Godot Engine
3. Run the main scene

## First Implementation Tasks

1. **Create Squad Movement System**
   - Implement basic squad entity with child units
   - Set up pathfinding with Navigation2D
   - Create basic movement controls

2. **Implement Cover Detection**
   - Define cover objects and properties
   - Create detection for units entering cover
   - Implement basic cover advantage system

3. **Design Isometric Grid**
   - Set up isometric tilemap
   - Implement proper depth sorting
   - Create camera controller

4. **Basic UI Elements**
   - Selection rectangle
   - Unit command feedback
   - Resource display

## Contributing

This is an open-source project and contributions are welcome! Please check the issues page for current tasks.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by Command & Conquer: Red Alert 2 and Company of Heroes
- Built with the amazing Godot Engine

