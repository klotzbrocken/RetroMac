import Metal
import MetalKit
import AppKit
import simd

struct ShaderUniforms {
    var mvp: simd_float4x4
    var outputSize: SIMD4<Float>
    var sourceSize: SIMD4<Float>
    var originalSize: SIMD4<Float>
    var finalViewportSize: SIMD4<Float>
    var frameCount: UInt32
    var frameDirection: Int32
    var intensity: Float
    var vignetteIntensity: Float = 0
}

final class RetroRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var currentPipeline: MTLRenderPipelineState?
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private var sampler: MTLSamplerState?
    private var tilingSampler: MTLSamplerState?
    private var vertexBuffer: MTLBuffer?
    private var frameCount: UInt32 = 0
    var intensity: Float = 1.0
    var vignetteIntensity: Float = 0

    // Overlay pipelines
    private var scanlinePipeline: MTLRenderPipelineState?
    private var reflectionPipeline: MTLRenderPipelineState?

    // Overlay textures (set externally by OverlayWindowController)
    var scanlineTexture: MTLTexture?
    var reflectionTexture: MTLTexture?
    var scanlineIntensity: Float = 1.0
    var reflectionIntensity: Float = 1.0

    private(set) var lastGPUTimeMs: Double = 0
    private var gpuSampleCounter: UInt32 = 0

    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.noCommandQueue
        }
        self.commandQueue = queue
        setupSampler()
        setupTilingSampler()
        setupVertexBuffer()
        try setupOverlayPipelines()
    }

    func loadShader(named name: String) throws {
        if let cached = pipelineCache[name] {
            currentPipeline = cached
            return
        }

        let library = try PresetRegistry.loadShader(named: name, device: device)

        guard let vertexFn = library.makeFunction(name: "vertex_main"),
              let fragmentFn = library.makeFunction(name: "fragment_main") else {
            throw RendererError.shaderFunctionNotFound
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let pipeline = try device.makeRenderPipelineState(descriptor: desc)
        pipelineCache[name] = pipeline
        currentPipeline = pipeline
    }

    func render(sourceTexture: MTLTexture, to drawable: CAMetalDrawable, viewportSize: CGSize, opaque: Bool = false) {
        guard let pipeline = currentPipeline,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        frameCount &+= 1

        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)
        let sw = Float(sourceTexture.width)
        let sh = Float(sourceTexture.height)

        var uniforms = ShaderUniforms(
            mvp: makeOrthographic(width: w, height: h),
            outputSize: SIMD4<Float>(w, h, 1.0 / w, 1.0 / h),
            sourceSize: SIMD4<Float>(sw, sh, 1.0 / sw, 1.0 / sh),
            originalSize: SIMD4<Float>(sw, sh, 1.0 / sw, 1.0 / sh),
            finalViewportSize: SIMD4<Float>(w, h, 1.0 / w, 1.0 / h),
            frameCount: frameCount,
            frameDirection: 1,
            intensity: intensity,
            vignetteIntensity: vignetteIntensity
        )

        let renderDesc = MTLRenderPassDescriptor()
        renderDesc.colorAttachments[0].texture = drawable.texture
        renderDesc.colorAttachments[0].loadAction = .clear
        renderDesc.colorAttachments[0].storeAction = .store
        renderDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: opaque ? 1 : 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDesc) else { return }

        // Pass 1: Main shader effect
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // Pass 2: Scanline overlay (multiply blend)
        if let scanTex = scanlineTexture, let scanPipe = scanlinePipeline {
            var opacity = scanlineIntensity
            encoder.setRenderPipelineState(scanPipe)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 1)
            encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 1)
            encoder.setFragmentTexture(scanTex, index: 0)
            encoder.setFragmentSamplerState(tilingSampler, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // Pass 3: Screen reflection (additive blend)
        if let reflTex = reflectionTexture, let reflPipe = reflectionPipeline {
            var opacity = reflectionIntensity
            encoder.setRenderPipelineState(reflPipe)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 1)
            encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 1)
            encoder.setFragmentTexture(reflTex, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()

        gpuSampleCounter &+= 1
        let shouldSample = gpuSampleCounter % 30 == 0
        if shouldSample {
            commandBuffer.addCompletedHandler { [weak self] buf in
                let gpuTime = (buf.gpuEndTime - buf.gpuStartTime) * 1000
                self?.lastGPUTimeMs = gpuTime
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func renderToImage(sourceTexture: MTLTexture, viewportSize: CGSize) -> NSImage? {
        guard let pipeline = currentPipeline,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }

        let w = Int(viewportSize.width)
        let h = Int(viewportSize.height)

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false
        )
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .managed
        guard let offscreen = device.makeTexture(descriptor: texDesc) else { return nil }

        let fw = Float(w)
        let fh = Float(h)
        let sw = Float(sourceTexture.width)
        let sh = Float(sourceTexture.height)

        var uniforms = ShaderUniforms(
            mvp: makeOrthographic(width: fw, height: fh),
            outputSize: SIMD4<Float>(fw, fh, 1.0 / fw, 1.0 / fh),
            sourceSize: SIMD4<Float>(sw, sh, 1.0 / sw, 1.0 / sh),
            originalSize: SIMD4<Float>(sw, sh, 1.0 / sw, 1.0 / sh),
            finalViewportSize: SIMD4<Float>(fw, fh, 1.0 / fw, 1.0 / fh),
            frameCount: frameCount,
            frameDirection: 1,
            intensity: intensity,
            vignetteIntensity: vignetteIntensity
        )

        let renderDesc = MTLRenderPassDescriptor()
        renderDesc.colorAttachments[0].texture = offscreen
        renderDesc.colorAttachments[0].loadAction = .clear
        renderDesc.colorAttachments[0].storeAction = .store
        renderDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDesc) else { return nil }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        if let scanTex = scanlineTexture, let scanPipe = scanlinePipeline {
            var opacity = scanlineIntensity
            encoder.setRenderPipelineState(scanPipe)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 1)
            encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 1)
            encoder.setFragmentTexture(scanTex, index: 0)
            encoder.setFragmentSamplerState(tilingSampler, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        if let reflTex = reflectionTexture, let reflPipe = reflectionPipeline {
            var opacity = reflectionIntensity
            encoder.setRenderPipelineState(reflPipe)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 1)
            encoder.setFragmentBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 1)
            encoder.setFragmentTexture(reflTex, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()

        let blitEncoder = commandBuffer.makeBlitCommandEncoder()
        blitEncoder?.synchronize(resource: offscreen)
        blitEncoder?.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytesPerRow = w * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * h)
        offscreen.getBytes(&pixels, bytesPerRow: bytesPerRow, from: MTLRegion(origin: .init(), size: .init(width: w, height: h, depth: 1)), mipmapLevel: 0)

        // BGRA → RGBA
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels.swapAt(i, i + 2)
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
    }

    // MARK: - Setup

    private func setupOverlayPipelines() throws {
        let overlayShaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct OverlayVertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        struct OverlayVertexData {
            packed_float2 position;
            packed_float2 texCoord;
        };

        struct OverlayUniforms {
            float4x4 mvp;
            float4 outputSize;
            float4 sourceSize;
            float4 originalSize;
            float4 finalViewportSize;
            uint frameCount;
            int frameDirection;
            float intensity;
            float vignetteIntensity;
        };

        vertex OverlayVertexOut overlay_vertex(
            uint vid [[vertex_id]],
            const device OverlayVertexData* vertices [[buffer(0)]],
            constant OverlayUniforms& uniforms [[buffer(1)]]
        ) {
            OverlayVertexOut out;
            out.position = float4(vertices[vid].position, 0.0, 1.0);
            out.texCoord = vertices[vid].texCoord;
            return out;
        }

        fragment float4 overlay_multiply_fragment(
            OverlayVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]],
            sampler s [[sampler(0)]],
            constant float& opacity [[buffer(0)]],
            constant OverlayUniforms& uniforms [[buffer(1)]]
        ) {
            // Tile the scanline texture across the full drawable
            float texH = float(tex.get_height());
            float2 tileUV = float2(0.0, in.texCoord.y * uniforms.outputSize.y / texH);
            float4 c = tex.sample(s, tileUV);
            // c.a encodes darkness: 1.0 = fully dark scanline, 0.0 = transparent gap
            float scanline = 1.0 - c.a * opacity * 0.8;
            return float4(scanline, scanline, scanline, 1.0);
        }

        fragment float4 overlay_additive_fragment(
            OverlayVertexOut in [[stage_in]],
            texture2d<float> tex [[texture(0)]],
            sampler s [[sampler(0)]],
            constant float& opacity [[buffer(0)]],
            constant OverlayUniforms& uniforms [[buffer(1)]]
        ) {
            float4 c = tex.sample(s, in.texCoord);
            // Scale down intensity significantly — additive blend accumulates fast
            float glare = c.a * opacity * 0.15;
            return float4(glare, glare, glare, 0.0);
        }
        """

        let library = try device.makeLibrary(source: overlayShaderSource, options: nil)
        guard let vertexFn = library.makeFunction(name: "overlay_vertex") else {
            throw RendererError.shaderFunctionNotFound
        }

        // Scanline: multiply blend (dst * src)
        if let fragFn = library.makeFunction(name: "overlay_multiply_fragment") {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertexFn
            desc.fragmentFunction = fragFn
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .zero
            desc.colorAttachments[0].destinationRGBBlendFactor = .sourceColor
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationAlphaBlendFactor = .one
            scanlinePipeline = try device.makeRenderPipelineState(descriptor: desc)
        }

        // Reflection: additive blend
        if let fragFn = library.makeFunction(name: "overlay_additive_fragment") {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertexFn
            desc.fragmentFunction = fragFn
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .one
            desc.colorAttachments[0].destinationRGBBlendFactor = .one
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationAlphaBlendFactor = .one
            reflectionPipeline = try device.makeRenderPipelineState(descriptor: desc)
        }
    }

    private func setupSampler() {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: desc)
    }

    private func setupTilingSampler() {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .nearest
        desc.magFilter = .nearest
        desc.sAddressMode = .repeat
        desc.tAddressMode = .repeat
        tilingSampler = device.makeSamplerState(descriptor: desc)
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

    private func makeOrthographic(width: Float, height: Float) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(2.0 / width, 0, 0, 0),
            SIMD4<Float>(0, 2.0 / height, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    enum RendererError: Error {
        case noCommandQueue
        case shaderFunctionNotFound
        case compilationFailed(String)
    }
}
