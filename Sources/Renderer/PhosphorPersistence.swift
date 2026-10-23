import Metal
import AppKit

/// Phosphor persistence — the afterglow a real CRT leaves behind.
///
/// Applied to the SIGNAL, before the mask/scanline shader — never after it. On a real tube the
/// beam only ever excites the phosphor dots at their fixed positions, so the glow decays behind
/// a mask that never moves. Accumulating the finished picture instead lets `max` fill in the dark
/// scanline rows the moment the image shifts by a pixel, and the mask washes out within seconds.
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
/// A monochrome monitor fades the way its phosphor did, in linear light, with the times RCA
/// measured (*Phosphors*, TPM-1508A, 1961) and the decay laws from Dyall (MIT RLE TR-56, 1948),
/// as tabulated by BURNIN (github.com/SnortingPixels/BURNIN, GPL-3): amber P3 and green P1 fade
/// exponentially, the IBM MDA's P39 drops to a tenth in 150 ms and then trails off as 1/t.
/// A colour tube's P22 is dark within a millisecond, so nothing real would show there: on colour
/// presets the afterglow is an effect, a plain half-life set by the slider.
///
/// Decay is derived from the real frame delta, so the trail lasts the same wall-clock time
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

    /// 0 = off, 1 = maximum afterglow. With a `phosphor`, 1 is the real tube and less is shorter;
    /// without one, a half-life of 8 to 110 ms.
    var persistence: Float = 0

    /// How a preset's screen lets go of a picture: `tau` in seconds, and the law. A phosphor fades
    /// exponentially or with the trap-limited 1/(1 + t/τ) tail; an STN LCD is slow both ways, so
    /// dark trails light as much as light trails dark.
    struct Phosphor: Equatable {
        enum Law { case exponential, hyperbolic, lcd }
        let tau: Double; let law: Law
    }
    static let p1 = Phosphor(tau: 0.0106, law: .exponential)   // green, 10 % after 24.5 ms
    static let p3 = Phosphor(tau: 0.0056, law: .exponential)   // amber, 10 % after 13 ms
    static let p39 = Phosphor(tau: 0.0167, law: .hyperbolic)   // IBM MDA green, 10 % after 150 ms, then 1/t
    static let dmgLCD = Phosphor(tau: 0.04, law: .lcd)         // the Game Boy's STN panel (estimate)

    /// Which phosphor a preset shows: its monitor's, or nil for a colour tube or a flat panel.
    static func phosphor(forPreset name: String) -> Phosphor? {
        switch name {
        case "amber-monitor": return p3
        case "green-phosphor": return p39   // the PC's green monochrome monitor: the MDA's smear
        case "terminal-green": return p1    // a green terminal (VT220 and kin)
        case "gameboy": return dmgLCD
        // White Phosphor's P4 and Orange Plasma's neon are dark within a millisecond: nothing to show.
        default: return nil
        }
    }

    var phosphor: Phosphor?

    private struct Params { var decay: SIMD3<Float>; var mode: Int32; var step: Float }

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

    /// Fold the incoming frame into the phosphor history and return the glowing signal to feed
    /// the CRT shader. Call BEFORE the main pass; returns `source` untouched when disabled.
    @discardableResult
    func accumulate(source: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture {
        guard persistence > 0.001 else {
            if lastWidth != 0 { reset() }   // turned off: forget the trail
            return source
        }
        guard source.pixelFormat == .bgra8Unorm else { return source }
        ensureTextures(width: source.width, height: source.height)
        guard let pipeline, let history = accum[writeIndex ^ 1], let target = accum[writeIndex] else { return source }

        // Frame-rate independent decay: convert the persistence slider into a half-life and work
        // out how much of the previous frame survives THIS frame's actual delta.
        let now = CACurrentMediaTime()
        let dt = (lastFrameTime > 0) ? min(max(now - lastFrameTime, 1.0 / 240.0), 0.25) : 1.0 / 60.0
        lastFrameTime = now
        let amount = Double(min(max(persistence, 0), 1))
        var params: Params
        if let p = phosphor {
            let tau = p.tau * amount
            switch p.law {
            case .exponential: params = Params(decay: SIMD3(repeating: Float(exp(-dt / tau))), mode: 1, step: 0)
            case .hyperbolic: params = Params(decay: .one, mode: 2, step: Float(dt / tau))
            case .lcd: params = Params(decay: SIMD3(repeating: Float(exp(-dt / tau))), mode: 3, step: 0)
            }
        } else {
            // 8 ms (barely a smear) up to ~110 ms (long 1950s-television trail).
            let base = Float(pow(0.5, dt / (0.008 + 0.102 * amount)))
            params = Params(decay: SIMD3(repeating: base), mode: 0, step: 0)
        }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return source }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(source, index: 0)    // this frame's signal
        encoder.setFragmentTexture(history, index: 1)   // what the phosphor still holds
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        writeIndex ^= 1
        return target       // the shader now draws the glowing signal, mask still crisp
    }

    // MARK: - Setup

    /// Half floats, not the signal's 8 bits: a dim glow decays by less than one 8-bit step per
    /// frame, rounds back up and would hang there for good.
    private func ensureTextures(width: Int, height: Int) {
        guard width != lastWidth || height != lastHeight || accum[0] == nil else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width,
                                                            height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
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

        struct Params { float3 decay; int mode; float step; };

        fragment float4 phosphor_fragment(PhosVertex in [[stage_in]],
                                          texture2d<float> current [[texture(0)]],
                                          texture2d<float> history [[texture(1)]],
                                          sampler s [[sampler(0)]],
                                          constant Params& p [[buffer(0)]]) {
            float4 cur = current.sample(s, in.texCoord);
            float3 old = history.sample(s, in.texCoord).rgb;
            // An LCD's crystals turn slowly towards whatever the picture is now, light or dark.
            if (p.mode == 3) return float4(mix(cur.rgb, old, p.decay), cur.a);
            if (p.mode == 0) {
                old *= p.decay;                       // the effect: a half-life on the signal
            } else {
                float3 lin = pow(max(old, 0.0), 2.2); // a phosphor fades in light, not in signal
                // ponytail: the 1/t law treats a dim pixel as an old bright one; exact per-pixel
                // age would need a second texture.
                lin = p.mode == 1 ? lin * p.decay : lin / (1.0 + lin * p.step);
                old = pow(lin, 1.0 / 2.2);
            }
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
        desc.colorAttachments[0].pixelFormat = .rgba16Float
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
