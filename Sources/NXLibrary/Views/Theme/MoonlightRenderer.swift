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
    var tintTop: SIMD4<Float>
    var tintMid: SIMD4<Float>
    var tintBottom: SIMD4<Float>
}

/// The moonlight's colors, as the shaders take them.
struct MoonlightColors: Equatable {
    var accent: SIMD3<Float>
    var ink: SIMD3<Float>
    /// How much of the Mods card's gold ground the shader draws under the light (0...1); glides with the accent.
    var tint: Float = 0
    /// The whole layer's opacity (0...1): the Mods card's moonlight over a wallpaper glides in and out with it.
    var presence: Float = 1

    init(accent: Color, ink: Color, tint: Float = 0, presence: Float = 1) {
        self.accent = Self.rgb(accent)
        self.ink = Self.rgb(ink)
        self.tint = tint
        self.presence = presence
    }

    /// The Mods card's ground (`SeleneBackdrop.modsGradient` at the base's 0.6 over the black scrim).
    static let tintTop = SIMD3<Float>(0x8A, 0x5A, 0x0E) / 255 * 0.6
    static let tintMid = SIMD3<Float>(0x3A, 0x25, 0x08) / 255 * 0.6
    static let tintBottom = SIMD3<Float>(0x05, 0x08, 0x0F) / 255 * 0.6

    private static func rgb(_ color: Color) -> SIMD3<Float> {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return SIMD3(1, 1, 1) }
        return SIMD3(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
    }
}

/// The device, the two pipelines and the particle field, made once and shared by
/// every moonlight on screen. Nil when Metal or the shaders are unavailable.
final class MoonlightEngine: @unchecked Sendable {
    // Pipelines, particle data and the command queue are immutable after init.
    // Every snapshot owns its texture and command buffer.
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
                                 look: SIMD4(breath, colors.presence, 0, 0),
                                 tintTop: SIMD4(MoonlightColors.tintTop, colors.tint),
                                 tintMid: SIMD4(MoonlightColors.tintMid, 0),
                                 tintBottom: SIMD4(MoonlightColors.tintBottom, 0))
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
        guard let drawable = layer.nextDrawable() else { return }
        render(into: drawable, uniforms: uniforms)
    }

    /// Renders one frame into a drawable the caller already has (a `CAMetalDisplayLink` update) and presents it.
    func render(into drawable: CAMetalDrawable, uniforms: MoonlightUniforms) {
        guard let buffer = queue.makeCommandBuffer() else { return }
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
///
/// On macOS 14 and later the link is a `CAMetalDisplayLink` asking for 60 fps: it tells the
/// system how often the motes change, so a variable-refresh display (ProMotion) keeps its
/// rate while nothing else on screen moves, and it hands over each drawable when the screen
/// can take it. A `CVDisplayLink` says neither: idle for ~10 s, the display slowed down and
/// `nextDrawable` waited up to 80 ms (measured: 60 fps fell to ~30). macOS 13 keeps it.
final class MoonlightLayerView: NSView {
    private let engine: MoonlightEngine
    private let metalLayer = CAMetalLayer()
    private var link: CVDisplayLink?
    /// The `CAMetalDisplayLink` (macOS 14+), held untyped for the macOS 13 build.
    private var metalLink: AnyObject?
    private var occlusion: NSObjectProtocol?

    /// Shared with the render thread, under `lock`.
    private struct State {
        var colors = MoonlightColors(accent: .white, ink: .white)
        /// A colour change glides from `from` over `blend` seconds (the Mods card's tint): only the uniform
        /// changes, the frame costs the same.
        var from: MoonlightColors?
        var blendStart: CFTimeInterval = 0
        var hasColors = false
        /// The last frame drawn from the link, for the frame-rate ceiling.
        var lastFrame: CFTimeInterval?
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
    /// How long a colour change glides.
    static let blend: CFTimeInterval = 1.2
    /// The frame rate's ceiling (a 120 Hz display draws every other refresh).
    private static let frameInterval = 1.0 / 60 - 0.002
    static let framesPerSecond: Float = 60

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
        if state.hasColors, colors != state.colors {
            // A change mid-glide starts from where the glide is now.
            state.from = Self.blended(state, at: CACurrentMediaTime())
            state.blendStart = CACurrentMediaTime()
        }
        state.hasColors = true
        state.colors = colors
        state.moving = moving
        if !moving { state.lastTick = nil }
        lock.unlock()
        updateLink()
        if !moving { renderFrame() }
    }

    /// Gone (presence 0, no glide): the layer is hidden and draws nothing, so a moonlight kept ready over a
    /// wallpaper costs nothing until the Mods card brings it in.
    private func isAbsent(at now: CFTimeInterval) -> Bool {
        state.colors.presence <= 0 && !blending(at: now)
    }

    private func updateVisibility() {
        lock.lock()
        let hidden = isAbsent(at: CACurrentMediaTime())
        lock.unlock()
        if metalLayer.isHidden != hidden {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            metalLayer.isHidden = hidden
            CATransaction.commit()
        }
    }

    func stop() {
        if let link { CVDisplayLinkStop(link) }
        link = nil
        stopMetalLink()
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
            // A running `CAMetalDisplayLink` owns the layer's drawables and draws the new size next.
            if metalLink == nil { renderFrame() }
        }
    }

    /// The colours at `now`: the glide's ease-in-out from `from` to `colors`, then `colors`.
    private static func blended(_ state: State, at now: CFTimeInterval) -> MoonlightColors {
        guard let from = state.from else { return state.colors }
        let t = min(max((now - state.blendStart) / blend, 0), 1)
        guard t < 1 else { return state.colors }
        let e = Float(t * t * (3 - 2 * t))
        var c = state.colors
        c.accent = from.accent + (c.accent - from.accent) * e
        c.ink = from.ink + (c.ink - from.ink) * e
        c.tint = from.tint + (c.tint - from.tint) * e
        c.presence = from.presence + (c.presence - from.presence) * e
        return c
    }

    private func blending(at now: CFTimeInterval) -> Bool {
        state.from != nil && now - state.blendStart < Self.blend
    }

    /// Runs the display link only while moving (or a colour glides), on screen and visible.
    private func updateLink() {
        lock.lock()
        let now = CACurrentMediaTime()
        let run = ((state.moving && !isAbsent(at: now)) || blending(at: now)) && state.visible && window != nil
        lock.unlock()
        updateVisibility()
        if #available(macOS 14.0, *) {
            if run { startMetalLink() } else { stopMetalLink() }
            return
        }
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

    @available(macOS 14.0, *)
    private func startMetalLink() {
        guard metalLink == nil else { return }
        let link = CAMetalDisplayLink(metalLayer: metalLayer)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Self.framesPerSecond / 2,
                                                        maximum: Self.framesPerSecond,
                                                        preferred: Self.framesPerSecond)
        let target = MoonlightLinkTarget(view: self)
        link.delegate = target
        metalLink = MoonlightLinkHandle(link: link, target: target)
        MoonlightRenderThread.shared.perform { link.add(to: .current, forMode: .default) }
    }

    /// Stops the link before anything else asks the layer for a drawable (a still frame).
    private func stopMetalLink() {
        guard let handle = metalLink as? MoonlightLinkHandle else { return }
        metalLink = nil
        if #available(macOS 14.0, *), let link = handle.link as? CAMetalDisplayLink { link.invalidate() }
    }

    /// The render thread, on the `CAMetalDisplayLink` (macOS 14+): `presentation` is when the frame shows.
    fileprivate func render(_ drawable: CAMetalDrawable, presentation: CFTimeInterval) {
        renderFrame(at: presentation, drawable: drawable)
    }

    /// The display link's thread.
    private func tick() {
        let now = CACurrentMediaTime()
        lock.lock()
        if let last = state.lastFrame, now - last < Self.frameInterval {
            lock.unlock()
            return
        }
        lock.unlock()
        renderFrame(at: now)
    }

    private func renderFrame(at now: CFTimeInterval = CACurrentMediaTime(), drawable: CAMetalDrawable? = nil) {
        lock.lock()
        if state.moving {
            // A late frame (the window was hidden or the link paused) never skips ahead.
            if let last = state.lastTick { state.clock += min(now - last, 0.1) }
            state.lastTick = now
        }
        state.lastFrame = now
        let clock = state.clock
        let colors = Self.blended(state, at: now)
        let glideEnded = state.from != nil && !blending(at: now)
        if glideEnded { state.from = nil }
        lock.unlock()
        // The glide is over: a still layer's link stops on its last frame, a gone one hides.
        if glideEnded { DispatchQueue.main.async { [weak self] in self?.updateLink() } }
        let size = metalLayer.drawableSize
        guard size.width >= 1, size.height >= 1 else { return }
        let breath = Float(0.5 + 0.5 * sin(2 * .pi * clock / MoonlightEngine.breathPeriod))
        let uniforms = MoonlightEngine.uniforms(width: Int(size.width), height: Int(size.height),
                                                time: Float(clock), breath: breath, colors: colors)
        if let drawable { engine.render(into: drawable, uniforms: uniforms) } else { engine.render(into: metalLayer, uniforms: uniforms) }
    }
}

/// The link and its delegate, kept together (the link holds its delegate weakly).
private final class MoonlightLinkHandle {
    let link: AnyObject
    let target: AnyObject
    init(link: AnyObject, target: AnyObject) { self.link = link; self.target = target }
}

@available(macOS 14.0, *)
private final class MoonlightLinkTarget: NSObject, CAMetalDisplayLinkDelegate {
    weak var view: MoonlightLayerView?
    init(view: MoonlightLayerView) { self.view = view }
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        view?.render(update.drawable, presentation: update.targetPresentationTimestamp)
    }
}

/// One thread with its own run loop for the moonlight's display links, so the motes never wait on the main thread.
private final class MoonlightRenderThread: Thread {
    static let shared: MoonlightRenderThread = {
        let thread = MoonlightRenderThread()
        thread.name = "Moonlight render"
        thread.qualityOfService = .userInteractive
        thread.start()
        thread.ready.wait()
        return thread
    }()

    private let ready = DispatchSemaphore(value: 0)
    private var loop: CFRunLoop?

    override func main() {
        loop = CFRunLoopGetCurrent()
        // A port keeps the run loop alive while no link is attached.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
    }

    /// Runs `work` on this thread's run loop.
    func perform(_ work: @escaping () -> Void) {
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(loop)
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
                // Keep the last frame while resizing. A cancelled request never
                // replaces the latest size/palette with a late result.
                do { try await Task.sleep(nanoseconds: 40_000_000) } catch { return }
                let frame = await Task.detached(priority: .userInitiated) {
                    engine.snapshot(width: w, height: h, colors: colors)
                }.value
                guard !Task.isCancelled else { return }
                image = frame
            }
        }
    }
}
