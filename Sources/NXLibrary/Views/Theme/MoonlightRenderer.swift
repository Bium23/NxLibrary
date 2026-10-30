import SwiftUI
import Metal
import QuartzCore
import CoreVideo
import NXLibraryCore

/// The shaders' uniforms, four float4s (see `MoonlightShaders`).
struct MoonlightUniforms {
    var size: SIMD4<Float>
    var accent: SIMD4<Float>
    var ink: SIMD4<Float>
    var look: SIMD4<Float>
}

/// The moonlight's colors, as the shaders take them.
struct MoonlightColors: Equatable {
    var accent: SIMD3<Float>
    var ink: SIMD3<Float>

    init(accent: Color, ink: Color) {
        self.accent = Self.rgb(accent)
        self.ink = Self.rgb(ink)
    }

    private static func rgb(_ color: Color) -> SIMD3<Float> {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return SIMD3(1, 1, 1) }
        return SIMD3(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
    }
}

/// The device, the two pipelines and the particle field, made once and shared by
/// every moonlight on screen. Nil when Metal or the shaders are unavailable.
final class MoonlightEngine {
    static let shared: MoonlightEngine? = MoonlightEngine()

    /// Breath period (s), and the time and breath of a still frame.
    static let breathPeriod = 7.0
    static let stillTime: Float = 24
    static let stillBreath: Float = 0.75

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let light: MTLRenderPipelineState
    private let dots: MTLRenderPipelineState
    private let field: MTLBuffer
    private let count: Int

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let particles = MoonlightField.particles()
        do {
            let library = try device.makeLibrary(source: MoonlightShaders.source, options: nil)
            func pipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = library.makeFunction(name: vertex)
                d.fragmentFunction = library.makeFunction(name: fragment)
                let color = d.colorAttachments[0]!
                color.pixelFormat = .bgra8Unorm
                // Light adds up.
                color.isBlendingEnabled = true
                color.rgbBlendOperation = .add
                color.alphaBlendOperation = .add
                color.sourceRGBBlendFactor = .one
                color.sourceAlphaBlendFactor = .one
                color.destinationRGBBlendFactor = .one
                color.destinationAlphaBlendFactor = .one
                return try device.makeRenderPipelineState(descriptor: d)
            }
            light = try pipeline("moon_full_vertex", "moon_light_fragment")
            dots = try pipeline("moon_dot_vertex", "moon_dot_fragment")
        } catch {
            NSLog("NX Library: moonlight shaders unavailable: \(error)")
            return nil
        }
        guard let buffer = particles.withUnsafeBytes({
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        }) else { return nil }
        self.device = device
        self.queue = queue
        self.field = buffer
        self.count = particles.count
    }

    static func uniforms(width: Int, height: Int, time: Float, breath: Float,
                         colors: MoonlightColors) -> MoonlightUniforms {
        let w = Float(max(width, 1)), h = Float(max(height, 1))
        return MoonlightUniforms(size: SIMD4(w, h, time, w / h),
                                 accent: SIMD4(colors.accent, 1),
                                 ink: SIMD4(colors.ink, 0),
                                 look: SIMD4(breath, 0, 0, 0))
    }

    private func encode(_ pass: MTLRenderPassDescriptor, _ buffer: MTLCommandBuffer, _ u: MoonlightUniforms) {
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var u = u
        encoder.setRenderPipelineState(light)
        encoder.setFragmentBytes(&u, length: MemoryLayout<MoonlightUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.setRenderPipelineState(dots)
        encoder.setVertexBuffer(field, offset: 0, index: 0)
        encoder.setVertexBytes(&u, length: MemoryLayout<MoonlightUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        encoder.endEncoding()
    }

    /// Renders one frame into the layer's next drawable and presents it. Safe
    /// from any thread: the render thread while moving, the main thread otherwise.
    func render(into layer: CAMetalLayer, uniforms: MoonlightUniforms) {
        guard let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        encode(pass, buffer, uniforms)
        buffer.present(drawable)
        buffer.commit()
    }

    /// One still frame as an image (the Theme screen's preview, clipped to its rounded card).
    func snapshot(width: Int, height: Int, colors: MoonlightColors) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height,
                                                         mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: d), let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        encode(pass, buffer, Self.uniforms(width: width, height: height, time: Self.stillTime,
                                          breath: Self.stillBreath, colors: colors))
        if texture.storageMode == .managed, let blit = buffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: texture)
            blit.endEncoding()
        }
        buffer.commit()
        buffer.waitUntilCompleted()
        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        texture.getBytes(&bytes, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                                                | CGImageAlphaInfo.premultipliedFirst.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// The moonlight live: up to 60 fps while `moving`, otherwise its last frame,
/// redrawn only on resize.
struct MoonlightMetalView: NSViewRepresentable {
    let engine: MoonlightEngine
    let colors: MoonlightColors
    let moving: Bool

    func makeNSView(context: Context) -> MoonlightLayerView { MoonlightLayerView(engine: engine) }

    func updateNSView(_ view: MoonlightLayerView, context: Context) {
        view.update(colors: colors, moving: moving)
    }

    static func dismantleNSView(_ view: MoonlightLayerView, coordinator: ()) { view.stop() }
}

/// A Metal layer drawn from a display link on its own thread, so a busy main
/// thread (a game's art arriving, the page laying out) never stalls the motes.
final class MoonlightLayerView: NSView {
    private let engine: MoonlightEngine
    private let metalLayer = CAMetalLayer()
    private var link: CVDisplayLink?
    private var occlusion: NSObjectProtocol?

    /// Shared with the render thread, under `lock`.
    private struct State {
        var colors = MoonlightColors(accent: .white, ink: .white)
        var moving = false
        var visible = true
        /// Seconds of motion so far: it stops while still and carries on from the
        /// same frame, so a game's art fading over or away never shows a jump.
        /// Starts part way in, so the motes are already spread along the road.
        var clock: Double = 40
        var lastTick: CFTimeInterval?
    }
    private var state = State()
    private let lock = NSLock()
    /// The frame rate's ceiling (a 120 Hz display draws every other refresh).
    private static let frameInterval = 1.0 / 60 - 0.002

    init(engine: MoonlightEngine) {
        self.engine = engine
        super.init(frame: .zero)
        metalLayer.device = engine.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.needsDisplayOnBoundsChange = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    deinit { stop() }

    override func makeBackingLayer() -> CALayer { metalLayer }

    /// The backdrop never takes the pointer.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(colors: MoonlightColors, moving: Bool) {
        lock.lock()
        state.colors = colors
        state.moving = moving
        if !moving { state.lastTick = nil }
        lock.unlock()
        updateLink()
        if !moving { renderFrame() }
    }

    func stop() {
        if let link { CVDisplayLinkStop(link) }
        link = nil
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
    }

    override func layout() {
        super.layout()
        resizeDrawable()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resizeDrawable()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
        if let window {
            occlusion = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in self?.windowVisibilityChanged() }
            windowVisibilityChanged()
            resizeDrawable()
        } else {
            updateLink()
        }
    }

    private func windowVisibilityChanged() {
        lock.lock()
        state.visible = window?.occlusionState.contains(.visible) ?? false
        lock.unlock()
        updateLink()
    }

    private func resizeDrawable() {
        let scale = window?.backingScaleFactor ?? 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size.width >= 1, size.height >= 1 else { return }
        metalLayer.contentsScale = scale
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
            renderFrame()
        }
    }

    /// Runs the display link only while moving, on screen and visible.
    private func updateLink() {
        lock.lock()
        let run = state.moving && state.visible && window != nil
        lock.unlock()
        if run {
            if link == nil {
                var created: CVDisplayLink?
                CVDisplayLinkCreateWithActiveCGDisplays(&created)
                guard let created else { return }
                CVDisplayLinkSetOutputCallback(created, { _, _, _, _, _, context in
                    guard let context else { return kCVReturnSuccess }
                    Unmanaged<MoonlightLayerView>.fromOpaque(context).takeUnretainedValue().tick()
                    return kCVReturnSuccess
                }, Unmanaged.passUnretained(self).toOpaque())
                link = created
            }
            if let link, !CVDisplayLinkIsRunning(link) { CVDisplayLinkStart(link) }
        } else if let link, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
    }

    /// The display link's thread.
    private func tick() {
        let now = CACurrentMediaTime()
        lock.lock()
        if let last = state.lastTick, now - last < Self.frameInterval {
            lock.unlock()
            return
        }
        lock.unlock()
        renderFrame(at: now)
    }

    private func renderFrame(at now: CFTimeInterval = CACurrentMediaTime()) {
        lock.lock()
        if state.moving {
            // A late frame (the window was hidden or the link paused) never skips ahead.
            if let last = state.lastTick { state.clock += min(now - last, 0.1) }
            state.lastTick = now
        }
        let clock = state.clock
        let colors = state.colors
        lock.unlock()
        let size = metalLayer.drawableSize
        guard size.width >= 1, size.height >= 1 else { return }
        let breath = Float(0.5 + 0.5 * sin(2 * .pi * clock / MoonlightEngine.breathPeriod))
        engine.render(into: metalLayer, uniforms: MoonlightEngine.uniforms(
            width: Int(size.width), height: Int(size.height),
            time: Float(clock), breath: breath, colors: colors))
    }
}

/// A still moonlight as an image, rendered once per size and palette.
struct MoonlightStill: View {
    let engine: MoonlightEngine
    let colors: MoonlightColors
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            let w = Int(geometry.size.width * scale), h = Int(geometry.size.height * scale)
            ZStack {
                if let image {
                    Image(decorative: image, scale: scale).resizable()
                }
            }
            .task(id: [w, h] + [colors.accent, colors.ink].flatMap { [$0.x, $0.y, $0.z].map { Int($0 * 255) } }) {
                image = engine.snapshot(width: w, height: h, colors: colors)
            }
        }
    }
}
