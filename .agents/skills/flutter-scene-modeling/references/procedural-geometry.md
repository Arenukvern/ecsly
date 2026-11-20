# Procedural geometry cookbook (flutter_scene 0.23.x)

All signatures below are verified against flutter_scene 0.23.0 source. Geometry
construction is pure Dart — you can assemble and even assert on vertex counts in a plain
`dart test` without a GPU; only submission touches the GPU.

## Imports

```dart
import 'package:flutter_scene/scene.dart'; // geometry, materials, Node, Scene
import 'package:flutter_scene/noise.dart'; // FastNoiseLite, noiseCurl3 (separate barrel — easy to forget)
import 'package:vector_math/vector_math.dart'; // NOT vector_math_64
```

## Built-in primitives (drop into `Mesh(geometry, material)`)

| Class | Key parameters (defaults) |
| --- | --- |
| `CuboidGeometry` | `Vector3 extents`, `{bool debugColors = false}` |
| `WedgeGeometry` | `Vector3 size` — right-angle wedge, the roof/ramp/chamfer workhorse |
| `PlaneGeometry` | `{width: 1, depth: 1, segmentsX: 1, segmentsZ: 1}` — XZ plane |
| `SphereGeometry` | `{radius: 0.5, segments: 32, rings: 16}` |
| `IcosphereGeometry` | `{radius: 0.5, subdivisions: 2}` — even triangles; lower subdivisions + noise displacement = low-poly organic |
| `CylinderGeometry` | `{bottomRadius: 0.5, topRadius: 0.5, height: 1, radialSegments: 32, heightSegments: 1}` — taper via different radii |
| `CapsuleGeometry` | `{radius: 0.5, height: 1, radialSegments: 32, capRings: 8}` — height is the cylinder mid-section; capsule = soft cuboid substitute |
| `TorusGeometry` | `{radius: 0.5, tubeRadius: 0.2, radialSegments: 32, tubularSegments: 16}` — raise `tubularSegments` for hero shots |
| `DiscGeometry` | `{radius: 0.5, segments: 32}` — flat, single-sided |
| `RingGeometry` | `{innerRadius: 0.25, outerRadius: 0.5, ...}` — planet rings, washers |

Wireframe of usage:

```dart
final body = Mesh(
  CapsuleGeometry(radius: 0.4, height: 0.6),
  PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.18, 0.20, 0.25, 1)
    ..metallicFactor = 0
    ..roughnessFactor = 0.35
    ..clearcoat = 0.6,
);
final torso = Node(mesh: body)..position = vm.Vector3(0, 0.8, 0);
root.add(torso);
```

## Swept geometry (the "designed" look comes from here)

Curves are `ScenePath` value types — `PolylinePath(List<Vector3>)` (≥ 2 points),
`CatmullRomPath(points)` (smooth through-points), `BezierPath(...)`. Frames are
rotation-minimizing, so swept profiles don't twist through bends.

- `TubeGeometry(path, {radius: 0.5, radialSegments: 12, stations: 64, caps: true})` —
  pipes, arms, cables, handlebars. `GeometryStorage.updatable` + `updatePath` re-sweeps in
  place (ropes, hoses).
- `ExtrudeGeometry(path, {required List<Vector2> profile, stations: 64, caps: true})` —
  profile is a **closed** polygon (≥ 3 `Vector2` in the path's normal plane): rectangular
  conduit, extruded signage, molded trim.
- `RibbonGeometry(...)` — flat ribbons along a path (banners, tracks, trails).

Recipe — an arm that bends (reads designed; a straight cylinder never does):

```dart
final armPath = CatmullRomPath([
  vm.Vector3(0, 0, 0),
  vm.Vector3(0.05, 0.45, 0.02),
  vm.Vector3(-0.08, 0.85, 0.06),
]);
final arm = Mesh(
  TubeGeometry(armPath, radius: 0.05, radialSegments: 16),
  lampMetal,
);
```

## Custom vertices

- `MeshAccumulator` — the lathe/loft workhorse: `addVertex(Vector3 position, Vector3
  normal, double u, double v) → int`, `addTriangle(a, b, c)`, `toArrays()` → feed
  `MeshGeometry.fromArrays(positions:, normals:, texCoords:, indices:)`.
- `GeometryBuilder` — fluent: `..normal(v).texCoord(uv).color(c)` sets current state,
  `addVertex(Vector3) → int` appends, `addTriangle(a, b, c)` chains. `deduplicate: true`
  by default.
- Do **not** hand-pack `ByteData` vertex buffers — the layout is fixed (72 bytes
  unskinned, fixed attribute order) and wrong strides fail silently (washed-out /
  see-through geometry). Always through `GeometryBuilder` / `fromArrays` /
  `MeshGeometry.fromMeshData`.

Recipe — a lathe (mushroom cap, vase, knob): rotate a 2D profile around Y:

```dart
Node buildLathe(List<vm.Vector2> profile, {int segments = 24}) {
  final acc = MeshAccumulator();
  for (var s = 0; s <= segments; s++) {
    final a = s / segments * 2 * math.pi;
    final cos = math.cos(a), sin = math.sin(a);
    for (final p in profile) {
      acc.addVertex(
        vm.Vector3(p.x * cos, p.y, p.x * sin),
        _ringNormal(p, cos, sin), // outward normal from the profile slope
        s / segments,
        0,
      );
    }
  }
  final ring = profile.length;
  for (var s = 0; s < segments; s++) {
    for (var i = 0; i < ring - 1; i++) {
      final a = s * ring + i, b = a + 1, c = a + ring, d = c + 1;
      acc.addTriangle(a, c, b);
      acc.addTriangle(b, c, d);
    }
  }
  final f = acc.toArrays();
  return Node(
    mesh: Mesh(
      MeshGeometry.fromArrays(
        positions: f.positions, normals: f.normals,
        texCoords: f.texCoords, indices: f.indices,
      ),
      PhysicallyBasedMaterial()..baseColorFactor = vm.Vector4(0.8, 0.3, 0.25, 1),
    ),
  );
}
```

## Instancing and scattering

```dart
InstancedMesh({
  required Geometry geometry,
  required Material material,
  bool cullInstances = false,
  bool sortTransparentInstances = true,
})
```

Thousands of copies in one draw call. Place with `FastNoiseLite(seed)` (OpenSimplex2,
Perlin, Cellular + fBm/ridged/domain-warp — deterministic per seed) or `noiseCurl3` for
flow-like fields. Per-instance transforms go through the instance APIs on `InstancedMesh`;
the official `flutter_scene-procedural` skill has the full pattern.

## Materials (factor recipes — no textures needed)

`PhysicallyBasedMaterial` setters: `baseColorFactor` (Vector4 RGBA), `metallicFactor`,
`roughnessFactor`, `normalScale`, `emissiveFactor` (Vector4) + `emissiveStrength`,
`occlusionStrength`, `specular`, `specularColor`, `ior`, `clearcoat`,
`clearcoatRoughness`, `sheenColor`, `sheenRoughness`, `transmission`,
`diffuseTransmission` + `diffuseTransmissionColor`, `thickness`, `attenuationDistance`,
`attenuationColor`, `dispersion`, `iridescence`, `iridescenceIor`, `alphaCutoff`.
Texture slots: `baseColorTexture`, `metallicRoughnessTexture`, `normalTexture`,
`emissiveTexture`, `occlusionTexture`. `UnlitMaterial` has `baseColorFactor` — for
markers, eyes, glow cores, screen-reading UI-in-3D.

| Look | Recipe |
| --- | --- |
| Matte plastic | metallic 0, roughness 0.6 |
| Glossy toy plastic | metallic 0, roughness 0.25, clearcoat 0.7, clearcoatRoughness 0.2 |
| Worn metal | metallic 1, roughness 0.45 |
| Polished metal | metallic 1, roughness 0.15, specular up |
| Rubber/grip | metallic 0, roughness 0.95 |
| Wood | metallic 0, roughness 0.7, warm baseColor |
| Glass | transmission 0.9, roughness 0.05, ior 1.5, thickness 0.1 |
| Emissive accent | UnlitMaterial, or emissiveFactor = color with emissiveStrength 2–5 |
| Frost/subsurface hint | diffuseTransmission 0.3 + attenuationColor |

Rules: baseColorFactor is linear RGB 0–1 (convert `0xFF4A9EFF` → r 0.29, g 0.60, b 1.0 —
not sRGB floats); one "hero" material trick per model (glass OR iridescence OR sheen), the
rest stay plain; unlit only where diegetic (screens, glow, markers), never for a whole lit
model.

## Node assembly and the copy trap

```dart
node.position = vm.Vector3(0, 1, 0);          // ✓ assign the whole value
node.position.y = 1;                          // ✗ getter returned a COPY — nothing moves
node.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.5);
node.scale = vm.Vector3.all(2);
```

Rotate parts around their own pivots by building the part centered on its pivot, then
positioning the node — never by compensating vertex offsets. Wheels: `CylinderGeometry` is
Y-axis; for a wheel on a car (Z-axis axle) build it, then set
`node.rotation = Quaternion.axisAngle(Vector3(1,0,0), pi/2)` and position; spinning the
wheel later is `node.rotate(...)` or a new quaternion on the same node.

## Tessellation budgets (then measure per the performance skill)

| Asset role | Triangle guidance |
| --- | --- |
| Scatter instance (foliage, debris) | 20–200 |
| Background prop | 200–1k |
| Hero prop | 1k–5k |
| Hero character | 3k–15k |
| Sphere segments / tube stations | 32/64 is plenty; only raise for close-up heroes |

These are starting points, not laws — desktop hides cost that mobile doesn't. Profile on
the lowest target you must support (`flutter_scene-performance` skill).
