# Godot Terrain Generator

Acerola's Dirt Jam

## What's in this branch

Triplanar texturing. One texture for low slopes, one for high slopes. 

![texturing](doc/texturing.png)

## What is there to learn

Not much... The formula for blending the two samples of the high slope texture (along planes x and z) gives more intensity to the sampling from which the surface normal is closest

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