import SceneKit

/// The things in the maze, built once and cloned per maze.
enum MazeModels {
    /// A little grey rat facing north (-z), standing on y = 0.
    static func rat() -> SCNNode {
        let fur = lambert(NSColor(white: 0.48, alpha: 1))
        let pink = lambert(NSColor(srgbRed: 0.85, green: 0.6, blue: 0.62, alpha: 1))
        let black = lambert(.black)
        let rat = SCNNode()
        func part(_ geometry: SCNGeometry, _ material: SCNMaterial, at position: SIMD3<Float>, scale: SIMD3<Float> = [1, 1, 1]) -> SCNNode {
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.simdPosition = position
            node.simdScale = scale
            rat.addChildNode(node)
            return node
        }
        _ = part(SCNSphere(radius: 0.13), fur, at: [0, 0.1, 0], scale: [0.85, 0.7, 1.5])
        _ = part(SCNSphere(radius: 0.08), fur, at: [0, 0.13, -0.22], scale: [0.9, 0.85, 1.3])
        _ = part(SCNSphere(radius: 0.022), pink, at: [0, 0.12, -0.33])
        for side in [-1, 1] as [Float] {
            _ = part(SCNSphere(radius: 0.042), pink, at: [side * 0.055, 0.2, -0.19], scale: [1, 1, 0.4])
            _ = part(SCNSphere(radius: 0.015), black, at: [side * 0.04, 0.16, -0.29])
        }
        let tail = part(SCNCylinder(radius: 0.012, height: 0.38), pink, at: [0, 0.06, 0.34])
        tail.simdEulerAngles = [.pi / 2 - 0.25, 0, 0]
        return rat
    }

    /// The grey shape that flips the world upside down: a flat-shaded octahedron.
    static func flipper() -> SCNNode {
        let r: Float = 0.32
        let tips: [SIMD3<Float>] = [[r, 0, 0], [-r, 0, 0], [0, r, 0], [0, -r, 0], [0, 0, r], [0, 0, -r]]
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        for x in [0, 1] {
            for y in [2, 3] {
                for z in [4, 5] {
                    var corners = [tips[x], tips[y], tips[z]]
                    var normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
                    // Wind every face outwards.
                    if simd_dot(normal, corners[0] + corners[1] + corners[2]) < 0 {
                        corners.swapAt(1, 2)
                        normal = -normal
                    }
                    positions += corners.map(SCNVector3.init)
                    normals += Array(repeating: SCNVector3(normal), count: 3)
                }
            }
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: (0..<UInt16(positions.count)).map { $0 }, primitiveType: .triangles)]
        )
        let material = SCNMaterial()
        material.lightingModel = .phong
        material.diffuse.contents = NSColor(white: 0.62, alpha: 1)
        material.specular.contents = NSColor(white: 0.9, alpha: 1)
        material.shininess = 0.4
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    /// The finish: a smiley coin, upright, for spinning about Y.
    static func smiley() -> SCNNode {
        let face = SCNMaterial()
        face.lightingModel = .constant
        face.diffuse.contents = MazeTextures.smiley()
        face.transparencyMode = .aOne
        let rim = SCNMaterial()
        rim.lightingModel = .constant
        rim.diffuse.contents = NSColor(srgbRed: 0.85, green: 0.65, blue: 0.05, alpha: 1)
        let coin = SCNCylinder(radius: 0.45, height: 0.05)
        coin.radialSegmentCount = 48
        // SCNCylinder's materials are side, top, bottom.
        coin.materials = [rim, face, face]
        let disc = SCNNode(geometry: coin)
        disc.simdEulerAngles = [.pi / 2, 0, 0]
        let spinner = SCNNode()
        spinner.addChildNode(disc)
        return spinner
    }

    private static func lambert(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = color
        return material
    }
}

/// Collects textured quads into one geometry, so a whole maze's walls are a single draw call.
struct QuadBuilder {
    private var positions: [SCNVector3] = []
    private var normals: [SCNVector3] = []
    private var textureCoordinates: [CGPoint] = []
    private var indices: [UInt32] = []

    /// A rectangle facing `normal`, `width` wide and `height` tall, its bottom edge centred on
    /// `base`; `up` is its upward direction. The texture spans it `repeats` times each way.
    mutating func addQuad(base: SIMD3<Float>, normal: SIMD3<Float>, up: SIMD3<Float>, width: Float, height: Float, repeats: SIMD2<Float> = [1, 1]) {
        let halfWidth: SIMD3<Float> = simd_cross(up, normal) * (width / 2)
        let rise: SIMD3<Float> = up * height
        let first = UInt32(positions.count)
        let corners: [SIMD3<Float>] = [base - halfWidth, base + halfWidth, base - halfWidth + rise, base + halfWidth + rise]
        let coordinates = [
            CGPoint(x: 0, y: CGFloat(repeats.y)), CGPoint(x: CGFloat(repeats.x), y: CGFloat(repeats.y)),
            CGPoint(x: 0, y: 0), CGPoint(x: CGFloat(repeats.x), y: 0),
        ]
        positions += corners.map(SCNVector3.init)
        normals += Array(repeating: SCNVector3(normal), count: 4)
        textureCoordinates += coordinates
        indices += [first, first + 1, first + 2, first + 1, first + 3, first + 2]
    }

    func geometry(material: SCNMaterial) -> SCNGeometry {
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: textureCoordinates),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.materials = [material]
        return geometry
    }
}
