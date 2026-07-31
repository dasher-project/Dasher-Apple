import SwiftUI
import AppKit
import Metal
import MetalKit
import simd

struct Strand2CubeView: NSViewRepresentable {
    let viewModel: MacDasherViewModel

    func makeNSView(context: Context) -> MetalCubeView {
        let view = MetalCubeView()
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ nsView: MetalCubeView, context: Context) {}
}

// MARK: - Metal view

final class MetalCubeView: MTKView {
    var viewModel: MacDasherViewModel?
    private var pipelineState: MTLRenderPipelineState!
    private var depthStencilState: MTLDepthStencilState!
    private var commandQueue: MTLCommandQueue!
    private var uniformBuffer: MTLBuffer!
    private var lastDebugPrint: TimeInterval = 0
    private var textOverlay: TextOverlayView!

    struct CubeVertex {
        var position: SIMD3<Float>
        var pad: Float = 0
        var color: SIMD4<Float>
    }

    struct Uniforms {
        var mvp: matrix_float4x4
    }

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()!
        super.init(frame: frameRect, device: metalDevice)
        setup()
    }

    convenience init() {
        self.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard let device else { fatalError("Metal device required") }

        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        clearColor = MTLClearColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1.0)
        preferredFramesPerSecond = 60
        isPaused = false
        framebufferOnly = true

        commandQueue = device.makeCommandQueue()
        buildPipeline(device: device)

        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: [])

        // Text overlay for labels
        textOverlay = TextOverlayView()
        textOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textOverlay)
        NSLayoutConstraint.activate([
            textOverlay.topAnchor.constraint(equalTo: topAnchor),
            textOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            textOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            textOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        delegate = self
    }

    private func buildPipeline(device: MTLDevice) {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunc = library.makeFunction(name: "cube_vertex"),
              let fragmentFunc = library.makeFunction(name: "cube_fragment") else {
            fatalError("Failed to load Metal shaders from CubeShaders.metal")
        }

        let desc = MTLVertexDescriptor()
        desc.attributes[0].format = .float3
        desc.attributes[0].offset = 0
        desc.attributes[0].bufferIndex = 0
        desc.attributes[1].format = .float4
        desc.attributes[1].offset = MemoryLayout<CubeVertex>.offset(of: \CubeVertex.color)!  // actual struct offset (16, not 12)
        desc.attributes[1].bufferIndex = 0
        desc.layouts[0].stride = MemoryLayout<CubeVertex>.stride

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.vertexDescriptor = desc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDesc.depthAttachmentPixelFormat = .depth32Float

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            fatalError("Failed to create Metal pipeline: \(error)")
        }

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        viewModel?.bridge.setVisibleNodesEnabled(true)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard superview != nil, let vm = viewModel, bounds.width > 100 else { return }
        vm.bridge.setScreenSize(width: Int(bounds.width), height: Int(bounds.height))
        vm.isPlaying = true
    }

    override func layout() {
        super.layout()
        guard let vm = viewModel, bounds.width > 100 else { return }
        vm.bridge.setScreenSize(width: Int(bounds.width), height: Int(bounds.height))
    }

    // MARK: Mouse input

    override func mouseDown(with event: NSEvent) {
        viewModel?.handleTouch(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        viewModel?.bridge.mouseMove(x: Float(pt.x), y: Float(pt.y))
    }

    override func mouseUp(with event: NSEvent) {
        viewModel?.handleTouchEnd()
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        viewModel?.bridge.mouseMove(x: Float(pt.x), y: Float(pt.y))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
}

// MARK: - Rendering

extension MetalCubeView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let vm = viewModel,
              let drawable = view.currentDrawable,
              let desc = view.currentRenderPassDescriptor,
              let cmd = commandQueue?.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { return }

        let viewWidth = Float(bounds.width)
        let viewHeight = Float(bounds.height)
        let drawW = Float(view.drawableSize.width)
        let drawH = Float(view.drawableSize.height)
        let timeMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        _ = vm.bridge.frame(timeMs: timeMs)
        vm.outputText = vm.bridge.getOutputText()
        vm.syncGameModeState()

        let nodes = vm.bridge.getVisibleNodes()

        let now = Date().timeIntervalSince1970
        if now - lastDebugPrint > 1.0 {
            lastDebugPrint = now
            print("[MetalCube] nodes=\(nodes.count) bounds=\(viewWidth)x\(viewHeight) drawable=\(drawW)x\(drawH)")
        }

        // Build vertex array — convert screen coords to NDC with isometric 3D skew
        var vertices: [CubeVertex] = []
        vertices.reserveCapacity(nodes.count * 36)

        for node in nodes {
            let ndcX1 = (Float(node.screenX1) / viewWidth) * 2.0 - 1.0
            let ndcX2 = (Float(node.screenX2) / viewWidth) * 2.0 - 1.0
            let ndcY1 = ((viewHeight - Float(node.screenY2)) / viewHeight) * 2.0 - 1.0
            let ndcY2 = ((viewHeight - Float(node.screenY1)) / viewHeight) * 2.0 - 1.0
            let w = ndcX2 - ndcX1
            let h = ndcY2 - ndcY1
            guard w > 0.001 && h > 0.001 else { continue }

            // 3D depth calculation & Z scaling:
            // Deeper nodes expand outward from their center to pop out toward the viewer in 3D space.
            let depthScale = 1.0 + Float(node.depth) * 0.10
            let cx = (ndcX1 + ndcX2) * 0.5
            let cy = (ndcY1 + ndcY2) * 0.5
            let wScaled = w * depthScale
            let hScaled = h * depthScale

            let fX1 = cx - wScaled * 0.5
            let fX2 = cx + wScaled * 0.5
            let fY1 = cy - hScaled * 0.5
            let fY2 = cy + hScaled * 0.5

            let depthZ = Float(node.depth) * 0.04
            let baseZ: Float = 0.85
            let centerZ = baseZ - depthZ
            let extrusionZ = min(max(hScaled * 0.25, 0.015), 0.10)
            let zFront = max(0.01, centerZ - extrusionZ)
            let zBack = min(0.99, centerZ + extrusionZ)

            // 3D block side-wall thickness (extruding top and right sides for isometric 3D block look)
            let extX = min(max(wScaled * 0.12, 0.015), 0.08)
            let extY = min(max(hScaled * 0.12, 0.015), 0.08)

            let col = argbToFloats(node.fillARGB)
            let r = col.x, g = col.y, b = col.z, a = col.w

            func c(_ s: Float) -> SIMD4<Float> {
                SIMD4<Float>(min(1, r * s), min(1, g * s), min(1, b * s), a)
            }

            let cf = c(1.0)   // Front face (base color)
            let cb = c(0.4)   // Back face (dark)
            let ct = c(1.25)  // Top face (highlight)
            let cr = c(0.65)  // Right face (shadow)
            let cl = c(0.85)  // Left face
            let cbn = c(0.50) // Bottom face

            // Front face (aligned at zFront, closest to viewer)
            vertices.append(contentsOf: [
                CubeVertex(position: SIMD3(fX1, fY1, zFront), color: cf),
                CubeVertex(position: SIMD3(fX2, fY1, zFront), color: cf),
                CubeVertex(position: SIMD3(fX2, fY2, zFront), color: cf),
                CubeVertex(position: SIMD3(fX1, fY1, zFront), color: cf),
                CubeVertex(position: SIMD3(fX2, fY2, zFront), color: cf),
                CubeVertex(position: SIMD3(fX1, fY2, zFront), color: cf),
            ])
            // Top face (highlighted roof of 3D block)
            vertices.append(contentsOf: [
                CubeVertex(position: SIMD3(fX1, fY2, zFront), color: ct),
                CubeVertex(position: SIMD3(fX2 + extX, fY2, zFront), color: ct),
                CubeVertex(position: SIMD3(fX2 + extX, fY2 + extY, zBack), color: ct),
                CubeVertex(position: SIMD3(fX1, fY2, zFront), color: ct),
                CubeVertex(position: SIMD3(fX2 + extX, fY2 + extY, zBack), color: ct),
                CubeVertex(position: SIMD3(fX1, fY2 + extY, zBack), color: ct),
            ])
            // Right face (shadowed side wall of 3D block)
            vertices.append(contentsOf: [
                CubeVertex(position: SIMD3(fX2, fY1, zFront), color: cr),
                CubeVertex(position: SIMD3(fX2 + extX, fY1, zBack), color: cr),
                CubeVertex(position: SIMD3(fX2 + extX, fY2 + extY, zBack), color: cr),
                CubeVertex(position: SIMD3(fX2, fY1, zFront), color: cr),
                CubeVertex(position: SIMD3(fX2 + extX, fY2 + extY, zBack), color: cr),
                CubeVertex(position: SIMD3(fX2, fY2, zFront), color: cr),
            ])
            // Back face (at zBack, offset by extX, extY)
            vertices.append(contentsOf: [
                CubeVertex(position: SIMD3(fX1, fY1, zBack), color: cb),
                CubeVertex(position: SIMD3(fX2 + extX, fY2 + extY, zBack), color: cb),
                CubeVertex(position: SIMD3(fX2 + extX, fY1, zBack), color: cb),
                CubeVertex(position: SIMD3(fX1, fY1, zBack), color: cb),
                CubeVertex(position: SIMD3(fX1, fY2 + extY, zBack), color: cb),
                CubeVertex(position: SIMD3(fX2 + extX, fY2 + extY, zBack), color: cb),
            ])
            // Left face
            vertices.append(contentsOf: [
                CubeVertex(position: SIMD3(fX1, fY1, zFront), color: cl),
                CubeVertex(position: SIMD3(fX1, fY2, zFront), color: cl),
                CubeVertex(position: SIMD3(fX1, fY2 + extY, zBack), color: cl),
                CubeVertex(position: SIMD3(fX1, fY1, zFront), color: cl),
                CubeVertex(position: SIMD3(fX1, fY2 + extY, zBack), color: cl),
                CubeVertex(position: SIMD3(fX1, fY1, zBack), color: cl),
            ])
            // Bottom face
            vertices.append(contentsOf: [
                CubeVertex(position: SIMD3(fX1, fY1, zFront), color: cbn),
                CubeVertex(position: SIMD3(fX2 + extX, fY1, zBack), color: cbn),
                CubeVertex(position: SIMD3(fX2, fY1, zFront), color: cbn),
                CubeVertex(position: SIMD3(fX1, fY1, zFront), color: cbn),
                CubeVertex(position: SIMD3(fX1, fY1, zBack), color: cbn),
                CubeVertex(position: SIMD3(fX2 + extX, fY1, zBack), color: cbn),
            ])
        }

        // Update text overlay
        let labels = vm.bridge.getVisibleNodeLabels()
        textOverlay.nodes = nodes
        textOverlay.labels = labels
        textOverlay.viewHeight = CGFloat(viewHeight)
        textOverlay.needsDisplay = true

        // Identity MVP (coords already in NDC)
        var identity = Uniforms(mvp: matrix_identity_float4x4)
        memcpy(uniformBuffer.contents(), &identity, MemoryLayout<Uniforms>.size)

        enc.setRenderPipelineState(pipelineState)
        enc.setDepthStencilState(depthStencilState)
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(drawW), height: Double(drawH), znear: 0, zfar: 1))
        enc.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        if !vertices.isEmpty {
            vertices.withUnsafeBytes { ptr in
                enc.setVertexBuffer(device!.makeBuffer(bytes: ptr.baseAddress!,
                                                        length: ptr.count,
                                                        options: [])!,
                                    offset: 0, index: 0)
            }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Projection

    private func buildMVP(width: Float, height: Float) -> matrix_float4x4 {
        // Perspective camera looking at the Dasher canvas from front-right
        // World: x=[0, width], y=[0, height], z=[-extrusionMax, 0]

        let aspect = width / max(height, 1)
        let fov: Float = 50.0 * .pi / 180.0
        let proj = perspectiveRH(fovY: fov, aspect: aspect, nearZ: 1, farZ: 5000)

        // Camera offset: shift right and up slightly, look at center of canvas
        let cx = width * 0.5
        let cy = height * 0.5
        let camDist: Float = max(width, height) * 1.3
        let eye = SIMD3<Float>(cx + camDist * 0.15, cy + camDist * 0.10, camDist)
        let target = SIMD3<Float>(cx, cy, -20)
        let up = SIMD3<Float>(0, 1, 0)
        let view = lookAtRH(eye: eye, target: target, up: up)

        return simd_mul(proj, view)
    }

    private func perspectiveRH(fovY: Float, aspect: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
        let f = 1.0 / tan(fovY / 2.0)
        let zRange = farZ - nearZ
        let A = -(farZ + nearZ) / zRange
        let B = -(2 * farZ * nearZ) / zRange
        return matrix_float4x4(columns: (
            SIMD4<Float>(f / aspect, 0, 0, 0),
            SIMD4<Float>(0, f, 0, 0),
            SIMD4<Float>(0, 0, A, -1),
            SIMD4<Float>(0, 0, B, 0)
        ))
    }

    private func lookAtRH(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
        let zAxis = simd_normalize(eye - target)
        let xAxis = simd_normalize(simd_cross(up, zAxis))
        let yAxis = simd_cross(zAxis, xAxis)
        return matrix_float4x4(columns: (
            SIMD4<Float>(xAxis.x, xAxis.y, xAxis.z, -simd_dot(xAxis, eye)),
            SIMD4<Float>(yAxis.x, yAxis.y, yAxis.z, -simd_dot(yAxis, eye)),
            SIMD4<Float>(zAxis.x, zAxis.y, zAxis.z, -simd_dot(zAxis, eye)),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    // MARK: - Helpers

    private func argbToFloats(_ argb: Int32) -> SIMD4<Float> {
        let r = Float((argb >> 16) & 0xFF) / 255.0
        let g = Float((argb >> 8) & 0xFF) / 255.0
        let b = Float(argb & 0xFF) / 255.0
        let a = Float((argb >> 24) & 0xFF) / 255.0
        return SIMD4<Float>(r, g, b, a)
    }
}

// MARK: - Text overlay

final class TextOverlayView: NSView {
    var nodes: [DasherBridge.VisibleNode] = []
    var labels: [String] = []
    var viewHeight: CGFloat = 0

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        guard !nodes.isEmpty else { return }

        let fontSize: CGFloat = 13
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]

        let viewWidth = bounds.width

        for node in nodes {
            guard node.labelIndex >= 0,
                  node.labelIndex < Int32(labels.count),
                  !labels[Int(node.labelIndex)].isEmpty else { continue }
            let text = labels[Int(node.labelIndex)]

            let depthScale = 1.0 + CGFloat(node.depth) * 0.12
            let cx = (CGFloat(node.screenX1) + CGFloat(node.screenX2)) * 0.5
            let cy = (CGFloat(node.screenY1) + CGFloat(node.screenY2)) * 0.5
            let wScaled = (CGFloat(node.screenX2) - CGFloat(node.screenX1)) * depthScale
            let hScaled = (CGFloat(node.screenY2) - CGFloat(node.screenY1)) * depthScale
            let fX1 = cx - wScaled * 0.5
            let fY1 = cy - hScaled * 0.5

            let x = fX1 + 4
            let y = fY1 + 3
            if x > -50 && x < viewWidth + 50 {
                NSAttributedString(string: text, attributes: attrs).draw(at: CGPoint(x: x, y: y))
            }
        }
    }
}
