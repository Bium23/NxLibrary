import SwiftUI
import MetalKit
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

    func draw(in view: MTKView, uniforms: MoonlightUniforms) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer() else { return }
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

/// The moonlight live: 30 fps while `moving`, otherwise its last frame, redrawn only on resize.
struct MoonlightMetalView: NSViewRepresentable {
    let engine: MoonlightEngine
    let colors: MoonlightColors
    let moving: Bool

    func makeCoordinator() -> Renderer { Renderer(engine: engine) }

    func makeNSView(context: Context) -> MTKView {
        let view = PassThroughMTKView(frame: .zero, device: engine.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 30
        view.layer?.isOpaque = false
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        let renderer = context.coordinator
        renderer.colors = colors
        renderer.moving = moving
        view.isPaused = !moving
        view.enableSetNeedsDisplay = !moving
        if !moving { view.needsDisplay = true }
    }

    final class Renderer: NSObject, MTKViewDelegate {
        let engine: MoonlightEngine
        var colors = MoonlightColors(accent: .white, ink: .white)
        var moving = true
        /// Seconds of motion so far: it stops while still and carries on from the
        /// same frame, so a game's art fading over or away never shows a jump.
        /// Starts part way in, so the motes are already spread along the band.
        private var clock: Double = 40
        private var lastTick: CFTimeInterval?

        init(engine: MoonlightEngine) { self.engine = engine }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            if !moving { view.needsDisplay = true }
        }

        func draw(in view: MTKView) {
            let now = CACurrentMediaTime()
            if moving {
                // A late frame (the view was hidden or paused) never skips ahead.
                if let lastTick { clock += min(now - lastTick, 0.1) }
                lastTick = now
            } else {
                lastTick = nil
            }
            let breath = Float(0.5 + 0.5 * sin(2 * .pi * clock / MoonlightEngine.breathPeriod))
            let size = view.drawableSize
            engine.draw(in: view, uniforms: MoonlightEngine.uniforms(
                width: Int(size.width), height: Int(size.height),
                time: Float(clock), breath: breath, colors: colors))
        }
    }
}

/// The backdrop never takes the pointer.
private final class PassThroughMTKView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
