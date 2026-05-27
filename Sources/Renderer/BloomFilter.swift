import Metal
import MetalKit
import MetalPerformanceShaders
import AppKit

/// GPU-accelerated bloom filter using MetalPerformanceShaders.
///
/// Inspired by RetroVisor's use of MPS for blur/resample operations.
/// Downsamples the source, applies Gaussian blur, then composites
/// the result additively to create a soft glow around bright areas.
final class BloomFilter {
    private let device: MTLDevice
    private var blurKernel: MPSImageGaussianBlur
    private var scaleKernel: MPSImageBilinearScale
    private var halfTexture: MTLTexture?
    private var blurredTexture: MTLTexture?
    private var compositePipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var vertexBuffer: MTLBuffer?
    private var lastWidth: Int = 0
    private var lastHeight: Int = 0

    /// Blur radius in pixels (at half resolution). Default 8.
    var radius: Float = 8.0 {
        didSet {
            if radius != oldValue {
                blurKernel = MPSImageGaussianBlur(device: device, sigma: radius)
                blurKernel.edgeMode = .clamp
            }
        }
    }

    /// Bloom intensity (0.0 = off, 1.0 = full). Default 0.3.
    var intensity: Float = 0.3

    /// Threshold for bloom — only pixels brighter than this contribute.
    /// 0.0 = everything blooms, 1.0 = only pure white. Default 0.4.
    var threshold: Float = 0.4

    init(device: MTLDevice) throws {
        self.device = device
        self.blurKernel = MPSImageGaussianBlur(device: device, sigma: 8.0)
        self.blurKernel.edgeMode = .clamp
        self.scaleKernel = MPSImageBilinearScale(device: device)
        try setupCompositePipeline()
        setupSampler()
        setupVertexBuffer()
    }

    /// Apply bloom as a post-process step within an existing command buffer.
    ///
    /// Call this AFTER all main render passes. It reads from the drawable's texture,
    /// creates a blurred version, and composites it back additively.
    ///
    /// - Parameters:
    ///   - source: The rendered frame texture (drawable.texture or intermediate)
    ///   - drawable: The drawable to composite bloom onto
    ///   - commandBuffer: Active command buffer (passes are appended)
    ///   - viewportSize: Viewport dimensions for the composite pass
    func apply(source: MTLTexture, drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer, viewportSize: CGSize) {
        guard intensity > 0 else { return }

        ensureTextures(width: source.width, height: source.height)
        guard let half = halfTexture, let blurred = blurredTexture else { return }

        // Step 1: Downsample source to half resolution (faster blur)
        scaleKernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: half)

        // Step 2: Gaussian blur at half resolution
        blurKernel.encode(commandBuffer: commandBuffer, inPlaceTexture: &halfTexture!, fallbackCopyAllocator: nil)

        // Step 3: Composite blurred half-res texture back onto drawable with additive blend
        let renderDesc = MTLRenderPassDescriptor()
        renderDesc.colorAttachments[0].texture = drawable.texture
        renderDesc.colorAttachments[0].loadAction = .load  // preserve existing content
        renderDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDesc),
              let pipeline = compositePipeline else { return }

        var bloomIntensity = intensity
        var bloomThreshold = threshold
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(half, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&bloomIntensity, length: MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentBytes(&bloomThreshold, length: MemoryLayout<Float>.size, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    /// Variant for IOSurface/texture targets (video recording, virtual camera)
    func apply(source: MTLTexture, target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard intensity > 0 else { return }

        ensureTextures(width: source.width, height: source.height)
        guard let half = halfTexture else { return }

        scaleKernel.encode(commandBuffer: commandBuffer, sourceTexture: source, destinationTexture: half)
        blurKernel.encode(commandBuffer: commandBuffer, inPlaceTexture: &halfTexture!, fallbackCopyAllocator: nil)

        let renderDesc = MTLRenderPassDescriptor()
        renderDesc.colorAttachments[0].texture = target
        renderDesc.colorAttachments[0].loadAction = .load
        renderDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDesc),
              let pipeline = compositePipeline else { return }

        var bloomIntensity = intensity
        var bloomThreshold = threshold
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(half, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&bloomIntensity, length: MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentBytes(&bloomThreshold, length: MemoryLayout<Float>.size, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    // MARK: - Private

    private func ensureTextures(width: Int, height: Int) {
        let halfW = max(width / 2, 1)
        let halfH = max(height / 2, 1)

        guard halfW != lastWidth || halfH != lastHeight else { return }
        lastWidth = halfW
        lastHeight = halfH

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: halfW, height: halfH, mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .private

        halfTexture = device.makeTexture(descriptor: desc)
        blurredTexture = device.makeTexture(descriptor: desc)

        print("[Bloom] Textures allocated: \(halfW)x\(halfH)")
    }

    private func setupCompositePipeline() throws {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct BloomVertex {
            float4 position [[position]];
            float2 texCoord;
        };

        struct VertexData {
            packed_float2 position;
            packed_float2 texCoord;
        };

        vertex BloomVertex bloom_vertex(
            uint vid [[vertex_id]],
            const device VertexData* vertices [[buffer(0)]]
        ) {
            BloomVertex out;
            out.position = float4(vertices[vid].position, 0.0, 1.0);
            out.texCoord = vertices[vid].texCoord;
            return out;
        }

        fragment float4 bloom_composite_fragment(
            BloomVertex in [[stage_in]],
            texture2d<float> blurTex [[texture(0)]],
            sampler s [[sampler(0)]],
            constant float& intensity [[buffer(0)]],
            constant float& threshold [[buffer(1)]]
        ) {
            float4 blurred = blurTex.sample(s, in.texCoord);
            // Soft threshold: only bloom bright areas
            float luminance = dot(blurred.rgb, float3(0.299, 0.587, 0.114));
            float bloomMask = smoothstep(threshold, threshold + 0.2, luminance);
            float3 bloom = blurred.rgb * bloomMask * intensity;
            return float4(bloom, 0.0);  // additive blend adds this to destination
        }
        """

        let library = try device.makeLibrary(source: shaderSource, options: nil)
        guard let vertexFn = library.makeFunction(name: "bloom_vertex"),
              let fragmentFn = library.makeFunction(name: "bloom_composite_fragment") else {
            throw BloomError.shaderCompileFailed
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Additive blend: dst + src
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .one
        desc.colorAttachments[0].destinationRGBBlendFactor = .one
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .one

        compositePipeline = try device.makeRenderPipelineState(descriptor: desc)
    }

    private func setupSampler() {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: desc)
    }

    private func setupVertexBuffer() {
        let vertices: [Float] = [
            -1, -1, 0, 1,
             1, -1, 1, 1,
            -1,  1, 0, 0,
             1,  1, 1, 0,
        ]
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size)
    }

    enum BloomError: Error {
        case shaderCompileFailed
    }
}
