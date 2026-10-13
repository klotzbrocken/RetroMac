import SceneKit

/// Pipe dimensions, in grid cells.
enum PipeMetrics {
    static let radius: Float = 0.15
    static let ballRadius: Float = 0.23
    /// Radius of an elbow's centre line. Must stay below 0.5 so back-to-back turns fit in one cell.
    static let bendRadius: Float = 0.25
    /// Scales the Utah teapot (body radius 2) to about one grid cell across, so it stands out from the ball joints.
    static let teapotScale: Float = 0.2
    /// Textures wrap once around a pipe; this repeats them along it at the same scale.
    static let textureRepeatsPerUnit: Float = 1 / (2 * .pi * radius)
}

/// Material and geometry shared by every piece of pipe of one colour or texture.
final class PipeKit {
    static let palette: [NSColor] = [
        NSColor(srgbRed: 0.86, green: 0.10, blue: 0.08, alpha: 1), // red
        NSColor(srgbRed: 0.10, green: 0.72, blue: 0.12, alpha: 1), // green
        NSColor(srgbRed: 0.12, green: 0.28, blue: 0.95, alpha: 1), // blue
        NSColor(srgbRed: 0.95, green: 0.82, blue: 0.08, alpha: 1), // yellow
        NSColor(srgbRed: 0.08, green: 0.78, blue: 0.84, alpha: 1), // cyan
        NSColor(srgbRed: 0.84, green: 0.14, blue: 0.84, alpha: 1), // magenta
        NSColor(srgbRed: 0.96, green: 0.48, blue: 0.08, alpha: 1), // orange
        NSColor(srgbRed: 0.82, green: 0.82, blue: 0.84, alpha: 1), // silver
    ]

    /// Straight runs are one unit-high cylinder scaled to their length, which would stretch a
    /// texture along the run; this scales the texture coordinates back to repeat instead.
    private static let repeatTextureAlongRun = """
        _geometry.texcoords[0].y *= length(scn_node.modelTransform[1].xyz) * \(PipeMetrics.textureRepeatsPerUnit)f;
        """

    /// Unit-length cylinder along Y; each straight run scales it to its length.
    let cylinder: SCNGeometry
    /// Rounded end at the start and end of a pipe.
    let cap: SCNGeometry
    let ball: SCNGeometry
    let elbow: SCNGeometry
    let teapot: SCNGeometry

    /// Around the pipe; shared by straight runs and elbows so they meet cleanly.
    private static let radialSegments = 24
    private let material: SCNMaterial
    /// Finished straight runs by length (in thousandths of a cell); runs come in only a few lengths.
    private var straightRuns: [Int: SCNGeometry] = [:]

    convenience init(color: NSColor) {
        let material = Self.makeMaterial(specular: 1)
        material.diffuse.contents = color
        self.init(material: material, runMaterial: material)
    }

    convenience init(texture: RetroTexture) {
        let material = Self.makeMaterial(specular: texture.specular)
        material.diffuse.contents = texture.makeImage()
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.mipFilter = .linear
        let runMaterial = material.copy() as! SCNMaterial
        runMaterial.shaderModifiers = [.geometry: Self.repeatTextureAlongRun]
        self.init(material: material, runMaterial: runMaterial)
    }

    private init(material: SCNMaterial, runMaterial: SCNMaterial) {
        self.material = material
        let radius = CGFloat(PipeMetrics.radius)
        let cylinder = SCNCylinder(radius: radius, height: 1)
        cylinder.radialSegmentCount = Self.radialSegments
        cylinder.materials = [runMaterial]
        let cap = SCNSphere(radius: radius)
        cap.segmentCount = 20
        let ball = SCNSphere(radius: CGFloat(PipeMetrics.ballRadius))
        ball.segmentCount = 24
        let elbow = Self.makeElbow(bendRadius: PipeMetrics.bendRadius, tubeRadius: PipeMetrics.radius)
        // Copies share the vertex data and only differ in material.
        let teapot = Teapot.geometry.copy() as! SCNGeometry

        for geometry in [cap, ball, elbow, teapot] {
            geometry.materials = [material]
        }
        self.cylinder = cylinder
        self.cap = cap
        self.ball = ball
        self.elbow = elbow
        self.teapot = teapot
    }

    /// A finished straight run, `length` long along Y. Unlike `cylinder` it isn't stretched by its
    /// node's scale, and repeats its texture along its length itself, so it can be merged.
    func straightRun(length: Float) -> SCNGeometry {
        let key = Int((length * 1000).rounded())
        if let geometry = straightRuns[key] {
            return geometry
        }
        let segments = Self.radialSegments
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var textureCoordinates: [CGPoint] = []
        for y in [-length / 2, length / 2] {
            for segment in 0...segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                let normal = SIMD3<Float>(cos(angle), 0, sin(angle))
                positions.append(SCNVector3(normal * PipeMetrics.radius + [0, y, 0]))
                normals.append(SCNVector3(normal))
                textureCoordinates.append(CGPoint(x: CGFloat(segment) / CGFloat(segments), y: CGFloat((y + length / 2) * PipeMetrics.textureRepeatsPerUnit)))
            }
        }
        var indices: [UInt16] = []
        for segment in 0..<segments {
            let a = UInt16(segment)
            let b = a + 1
            let c = a + UInt16(segments + 1)
            let d = c + 1
            indices += [a, c, b, b, c, d]
        }
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: textureCoordinates),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.materials = [material]
        straightRuns[key] = geometry
        return geometry
    }

    private static func makeMaterial(specular: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .phong
        material.specular.contents = NSColor(white: specular, alpha: 1)
        material.shininess = 0.35
        material.locksAmbientWithDiffuse = true
        return material
    }

    /// A quarter torus. In local space the pipe enters at (0, -R, 0) heading +X and
    /// leaves at (R, 0, 0) heading +Y, bending around the origin.
    private static func makeElbow(bendRadius: Float, tubeRadius: Float, bendSegments: Int = 10, tubeSegments: Int = radialSegments) -> SCNGeometry {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var textureCoordinates: [CGPoint] = []
        for i in 0...bendSegments {
            let theta = Float(i) / Float(bendSegments) * .pi / 2
            let outward = SIMD3<Float>(sin(theta), -cos(theta), 0)
            let spine = outward * bendRadius
            // Same texture scale as a straight run: once around, repeating along the centre line.
            let along = theta * bendRadius * PipeMetrics.textureRepeatsPerUnit
            for j in 0...tubeSegments {
                let phi = Float(j) / Float(tubeSegments) * 2 * .pi
                let normal = outward * cos(phi) + SIMD3<Float>(0, 0, 1) * sin(phi)
                positions.append(SCNVector3(spine + normal * tubeRadius))
                normals.append(SCNVector3(normal))
                textureCoordinates.append(CGPoint(x: CGFloat(j) / CGFloat(tubeSegments), y: CGFloat(along)))
            }
        }

        var indices: [UInt16] = []
        let stride = tubeSegments + 1
        for i in 0..<bendSegments {
            for j in 0..<tubeSegments {
                let a = UInt16(i * stride + j)
                let b = UInt16((i + 1) * stride + j)
                let c = a + 1
                let d = b + 1
                indices += [a, b, c, b, d, c]
            }
        }

        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: textureCoordinates),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }
}
