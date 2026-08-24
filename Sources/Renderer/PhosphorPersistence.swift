import Metal
import AppKit

/// Phosphor persistence — the afterglow a real CRT leaves behind.
///
/// A shader can fake a phosphor *mask* within a single frame, but genuine persistence is a
/// property of TIME: excited phosphor keeps emitting after the beam has moved on, decaying
/// exponentially. That needs the previous frame, which a single-pass shader never sees.
///
/// This keeps a ping-pong pair of accumulation textures and, each frame, folds the freshly
/// rendered image into the decayed history:
///
///     accum = max(current, history * decay)
///
/// `max` (rather than an average) is what produces a trailing glow instead of a muddy blur:
/// a bright pixel lights the phosphor instantly, then fades on its own.
///
/// Decay is per-channel because P22 phosphors do not fade evenly — green (ZnS:Cu,Au,Al) lingers
/// longest, red sits in the middle, blue (ZnS:Ag) dies fastest. That imbalance is why CRT trails
/// drift green, and reproducing it is most of what sells the effect.
///
/// Decay is also derived from the real frame delta, so the trail lasts the same wall-clock time
/// at 24, 30 or 120 fps instead of getting shorter as the frame rate climbs.
final class PhosphorPersistence {

    enum PhosphorError: Error { case shaderCompileFailed }

    private let device: MTLDevice
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var vertexBuffer: MTLBuffer?

    /// Ping-pong accumulation buffers: one is read as history while the other is written.
    private var accum: [MTLTexture?] = [nil, nil]
    private var writeIndex = 0
    private var lastWidth = 0
    private var lastHeight = 0
    private var lastFrameTime: CFTimeInterval = 0

    /// 0 = off, 1 = maximum afterglow. Maps to a phosphor half-life, not a raw per-frame factor.
    var persistence: Float = 0

    init(device: MTLDevice) throws {
        self.device = device
        try setupPipeline()
        setupSampler()
        setupVertexBuffer()
    }

    /// Drop the accumulated history (theme/shader switch, or when the effect is turned off) so a
    /// stale image cannot bleed into the next thing shown.
    func reset() {
        accum = [nil, nil]
        lastWidth = 0; lastHeight = 0
        lastFrameTime = 0
    }

    /// Fold the drawable's current contents into the phosphor history and write the glowing
    /// result back to the drawable. Call AFTER the shader/scanline/bloom passes.
    func apply(drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer) {
        guard persistence > 0.001 else {
            if lastWidth != 0 { reset() }   // turned off: forget the trail
            return
        }
        let tex = drawable.texture
        ensureTextures(width: tex.width, height: tex.height, format: tex.pixelFormat)
        guard let pipeline, let history = accum[writeIndex ^ 1], let target = accum[writeIndex] else { return }

        // Frame-rate independent decay: convert the persistence slider into a half-life and work
        // out how much of the previous frame survives THIS frame's actual delta.
        let now = CACurrentMediaTime()
        let dt = (lastFrameTime > 0) ? min(max(now - lastFrameTime, 1.0 / 240.0), 0.25) : 1.0 / 60.0
        lastFrameTime = now
        // 8 ms (barely a smear) up to ~110 ms (long 1950s-television trail).
        let halfLife = Double(0.008 + 0.102 * min(max(persistence, 0), 1))
        let base = Float(pow(0.5, dt / halfLife))
        // Per-channel: green lingers, blue fades first.
        var decay = SIMD3<Float>(base * 0.97, base, base * 0.90)

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(tex, index: 0)       // this frame
        encoder.setFragmentTexture(history, index: 1)   // what the phosphor still holds
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&decay, length: MemoryLayout<SIMD3<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        // Show the accumulated result.
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(from: target, to: tex)
            blit.endEncoding()
        }
        writeIndex ^= 1
    }

    // MARK: - Setup

    private func ensureTextures(width: Int, height: Int, format: MTLPixelFormat) {
        guard width != lastWidth || height != lastHeight || accum[0] == nil else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width,
                                                            height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead, .shaderWrite]
        desc.storageMode = .private
        accum = [device.makeTexture(descriptor: desc), device.makeTexture(descriptor: desc)]
        lastWidth = width; lastHeight = height
        lastFrameTime = 0
    }

    private func setupPipeline() throws {
        let src = """
        #include <metal_stdlib>
        using namespace metal;

        struct PhosVertex { float4 position [[position]]; float2 texCoord; };
        struct VertexData { packed_float2 position; packed_float2 texCoord; };

        vertex PhosVertex phosphor_vertex(uint vid [[vertex_id]],
                                          const device VertexData* verts [[buffer(0)]]) {
            PhosVertex out;
            out.position = float4(verts[vid].position, 0.0, 1.0);
            out.texCoord = verts[vid].texCoord;
            return out;
        }

        fragment float4 phosphor_fragment(PhosVertex in [[stage_in]],
                                          texture2d<float> current [[texture(0)]],
                                          texture2d<float> history [[texture(1)]],
                                          sampler s [[sampler(0)]],
                                          constant float3& decay [[buffer(0)]]) {
            float4 cur = current.sample(s, in.texCoord);
            float3 old = history.sample(s, in.texCoord).rgb * decay;
            // The beam re-lights a pixel instantly; otherwise the old glow just fades.
            return float4(max(cur.rgb, old), cur.a);
        }
        """
        let library = try device.makeLibrary(source: src, options: nil)
        guard let vfn = library.makeFunction(name: "phosphor_vertex"),
              let ffn = library.makeFunction(name: "phosphor_fragment") else {
            throw PhosphorError.shaderCompileFailed
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: desc)
    }

    private func setupSampler() {
        let d = MTLSamplerDescriptor()
        d.minFilter = .nearest; d.magFilter = .nearest
        d.sAddressMode = .clampToEdge; d.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: d)
    }

    private func setupVertexBuffer() {
        let verts: [Float] = [-1, -1, 0, 1,
                               1, -1, 1, 1,
                              -1,  1, 0, 0,
                               1,  1, 1, 0]
        vertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.size)
    }
}
