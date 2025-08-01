# Godot Terrain Generator

Submission for Acerola's Dirt Jam

No gameplay, just an UI to walk through the features implemented

Implemented features :
- Proper normals
- Precomputed noise texture
- Cast shadows
- Shader iclude system

Each feature has its own branch. The branch jam puts them all together


![walkthrough](doc/walkthrough.png)

---

by Acerola

Implements simple perlin noise based fractional brownian motion as a Godot compositor effect for use as a base or reference in my event [Dirt Jam](https://itch.io/jam/acerola-dirt-jam/).

![example](doc/example.png)

## How To Use

* Create a new godot project with a 3D root node
* Add `DirectionalLight3D`, `Camera3D`, and `WorldEnvironment` nodes to the scene
* Add a `Compositor` to the `WorldEnvironment` node
* Add an element to the `Compositor Effects` array
* Instantiate a new `DrawTerrainMesh` in the element field
* Click the box to open the settings list for the terrain, hover over settings to get an explanation for what it does!
