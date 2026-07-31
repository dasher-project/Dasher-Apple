# Strand 2 — 3D Cube Rendering Progress

## Status: Experimental, paused

## What works
- **Strand 2 API** (DasherCore PR #51): `dasher_set_visible_nodes_enabled`, `dasher_get_visible_nodes`, `dasher_get_viewport` — all proven end-to-end
- **Metal pipeline**: MTKView + CubeShaders.metal builds and runs. Depth buffer, vertex buffer creation, text overlay (TextOverlayView) all functional
- **Node data arrives correctly**: 40-70 nodes per frame with screen coords, colors, labels, depth
- **Input works**: mouse move/down/up drives the engine normally through the MetalCubeView

## What doesn't work yet
- **3D visual effect is unconvincing**: Cubes render as flat colored rectangles with a subtle isometric skew. The 3D extrusion is barely visible because Dasher nodes are thin horizontal strips, not boxes
- **All cubes at similar depth**: Without a perspective camera, the depth-based z-offsetting (children protrude from parents) doesn't create a convincing 3D landscape
- **Perspective projection was attempted but failed**: Custom `perspectiveRH` + `lookAtRH` matrix functions produced a black screen. The identity MVP + NDC coordinate approach works but is orthographic only

## Known issues to fix
1. **Vertex descriptor offset**: Fixed — use `MemoryLayout<CubeVertex>.offset(of: \.color)!` not `MemoryLayout<SIMD3<Float>>.stride`
2. **Viewport must use `drawableSize`** (pixels) not `bounds` (points) — Retina displays need 2x
3. **MTKView init**: Must provide `convenience init()` that passes `MTLCreateSystemDefaultDevice()` — the parameterless init path leaves device as nil
4. **Perspective projection**: The custom matrix functions need debugging. The orthographic (identity MVP) path works. To get real perspective, the MVP matrix needs to be validated against known-good Metal projection code

## Next steps (when resuming)
1. **Debug the perspective projection**: Write a minimal test with known vertices (e.g., a cube at origin) and verify the MVP transforms them to visible NDC. Compare with Apple's Metal sample code projections
2. **Consider MetalKit's built-in camera helpers** or use a battle-tested matrix library (e.g., from Apple's Metal sample code or simd helpers)
3. **Text rendering**: Current TextOverlayView works but redraws all labels every frame. For production, consider texture atlas or Metal text rendering
4. **Clean up demo toggle**: The "3D Cubes" toolbar toggle in MacContentView.swift switches between MacCanvasView and Strand2CubeView. For shipping, decide whether to keep this as an option or replace the default canvas
5. **Performance**: Per-frame MTLBuffer creation (`device.makeBuffer`) is fine for 70 nodes but could use buffer pooling for larger node counts

## Architecture notes
- `Strand2CubeView.swift` — MTKView subclass + MTKViewDelegate, handles rendering + input
- `CubeShaders.metal` — Simple vertex (MVP transform) + fragment (pass-through color) shaders
- `DasherBridge.swift` — `VisibleNode` struct, `setVisibleNodesEnabled`, `getVisibleNodes`, `getVisibleNodeLabels` wrappers
- `MacContentView.swift` — `canvasView` computed property, `useStrand2Demo` toggle
- DasherCore submodule at PR #51 commit (`2cc0ebe0`) — provides the Strand 2 C API

## Branch
- `experiment/strand2-demo` on Dasher-Apple
- DasherCore PR #51 on the submodule
