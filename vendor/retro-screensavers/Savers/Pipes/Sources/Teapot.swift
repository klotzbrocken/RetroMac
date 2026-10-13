import SceneKit

/// The Utah teapot, tessellated from Martin Newell's Bézier patches (the set distributed with GLUT).
/// Windows Pipes would very occasionally draw one in place of a ball joint.
enum Teapot {
    /// Y-up, centred on the widest part of the body, which has radius 2; spout to handle spans about 6.5.
    static let geometry = makeGeometry(subdivisions: 10)

    /// 16 control point indices per patch, as 4 rows of 4.
    private static let patches: [[Int]] = [
        [102, 103, 104, 105, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],             // rim
        [12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27],           // body
        [24, 25, 26, 27, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40],
        [96, 96, 96, 96, 97, 98, 99, 100, 101, 101, 101, 101, 0, 1, 2, 3],          // lid
        [0, 1, 2, 3, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117],
        [118, 118, 118, 118, 124, 122, 119, 121, 123, 126, 125, 120, 40, 39, 38, 37], // bottom
        [41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56],           // handle
        [53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 28, 65, 66, 67],
        [68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83],           // spout
        [80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95],
    ]

    /// Rim, body, lid and bottom are mirrored into all four quadrants; handle and spout only across y = 0.
    private static let fourWayPatchCount = 6

    /// Z-up, as in the original data set.
    private static let controlPoints: [SIMD3<Float>] = [
        [0.2, 0, 2.7], [0.2, -0.112, 2.7], [0.112, -0.2, 2.7], [0, -0.2, 2.7],
        [1.3375, 0, 2.53125], [1.3375, -0.749, 2.53125], [0.749, -1.3375, 2.53125], [0, -1.3375, 2.53125],
        [1.4375, 0, 2.53125], [1.4375, -0.805, 2.53125], [0.805, -1.4375, 2.53125], [0, -1.4375, 2.53125],
        [1.5, 0, 2.4], [1.5, -0.84, 2.4], [0.84, -1.5, 2.4], [0, -1.5, 2.4],
        [1.75, 0, 1.875], [1.75, -0.98, 1.875], [0.98, -1.75, 1.875], [0, -1.75, 1.875],
        [2, 0, 1.35], [2, -1.12, 1.35], [1.12, -2, 1.35], [0, -2, 1.35],
        [2, 0, 0.9], [2, -1.12, 0.9], [1.12, -2, 0.9], [0, -2, 0.9],
        [-2, 0, 0.9],
        [2, 0, 0.45], [2, -1.12, 0.45], [1.12, -2, 0.45], [0, -2, 0.45],
        [1.5, 0, 0.225], [1.5, -0.84, 0.225], [0.84, -1.5, 0.225], [0, -1.5, 0.225],
        [1.5, 0, 0.15], [1.5, -0.84, 0.15], [0.84, -1.5, 0.15], [0, -1.5, 0.15],
        [-1.6, 0, 2.025], [-1.6, -0.3, 2.025], [-1.5, -0.3, 2.25], [-1.5, 0, 2.25],
        [-2.3, 0, 2.025], [-2.3, -0.3, 2.025], [-2.5, -0.3, 2.25], [-2.5, 0, 2.25],
        [-2.7, 0, 2.025], [-2.7, -0.3, 2.025], [-3, -0.3, 2.25], [-3, 0, 2.25],
        [-2.7, 0, 1.8], [-2.7, -0.3, 1.8], [-3, -0.3, 1.8], [-3, 0, 1.8],
        [-2.7, 0, 1.575], [-2.7, -0.3, 1.575], [-3, -0.3, 1.35], [-3, 0, 1.35],
        [-2.5, 0, 1.125], [-2.5, -0.3, 1.125], [-2.65, -0.3, 0.9375], [-2.65, 0, 0.9375],
        [-2, -0.3, 0.9], [-1.9, -0.3, 0.6], [-1.9, 0, 0.6],
        [1.7, 0, 1.425], [1.7, -0.66, 1.425], [1.7, -0.66, 0.6], [1.7, 0, 0.6],
        [2.6, 0, 1.425], [2.6, -0.66, 1.425], [3.1, -0.66, 0.825], [3.1, 0, 0.825],
        [2.3, 0, 2.1], [2.3, -0.25, 2.1], [2.4, -0.25, 2.025], [2.4, 0, 2.025],
        [2.7, 0, 2.4], [2.7, -0.25, 2.4], [3.3, -0.25, 2.4], [3.3, 0, 2.4],
        [2.8, 0, 2.475], [2.8, -0.25, 2.475], [3.525, -0.25, 2.49375], [3.525, 0, 2.49375],
        [2.9, 0, 2.475], [2.9, -0.15, 2.475], [3.45, -0.15, 2.5125], [3.45, 0, 2.5125],
        [2.8, 0, 2.4], [2.8, -0.15, 2.4], [3.2, -0.15, 2.4], [3.2, 0, 2.4],
        [0, 0, 3.15], [0.8, 0, 3.15], [0.8, -0.45, 3.15], [0.45, -0.8, 3.15], [0, -0.8, 3.15],
        [0, 0, 2.85],
        [1.4, 0, 2.4], [1.4, -0.784, 2.4], [0.784, -1.4, 2.4], [0, -1.4, 2.4],
        [0.4, 0, 2.55], [0.4, -0.224, 2.55], [0.224, -0.4, 2.55], [0, -0.4, 2.55],
        [1.3, 0, 2.55], [1.3, -0.728, 2.55], [0.728, -1.3, 2.55], [0, -1.3, 2.55],
        [1.3, 0, 2.4], [1.3, -0.728, 2.4], [0.728, -1.3, 2.4], [0, -1.3, 2.4],
        [0, 0, 0], [1.425, -0.798, 0], [1.5, 0, 0.075], [1.425, 0, 0],
        [0.798, -1.425, 0], [0, -1.5, 0.075], [0, -1.425, 0], [1.5, -0.84, 0.075],
        [0.84, -1.5, 0.075],
    ]

    /// Height of the body's widest point in the original data, used as the centre.
    private static let centerHeight: Float = 1.35

    private static func makeGeometry(subdivisions n: Int) -> SCNGeometry {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var textureCoordinates: [CGPoint] = []
        var indices: [UInt16] = []

        for (patchIndex, patch) in patches.enumerated() {
            let points = patch.map { controlPoints[$0] }
            var mirrors: [SIMD3<Float>] = [[1, 1, 1], [1, -1, 1]]
            if patchIndex < fourWayPatchCount {
                mirrors += [[-1, 1, 1], [-1, -1, 1]]
            }

            for mirror in mirrors {
                let base = positions.count
                for row in 0...n {
                    for column in 0...n {
                        let u = Float(column) / Float(n)
                        let v = Float(row) / Float(n)
                        let position = evaluate(points, bernstein(u), bernstein(v)) * mirror
                        // Lid top and bottom centre are degenerate; take derivatives just inside the patch.
                        let du = derivativeParameter(u)
                        let dv = derivativeParameter(v)
                        let tangentU = evaluate(points, bernsteinDerivative(du), bernstein(dv))
                        let tangentV = evaluate(points, bernstein(du), bernsteinDerivative(dv))
                        let normal = simd_normalize(simd_cross(tangentU, tangentV)) * mirror
                        positions.append(SCNVector3(yUp(position - [0, 0, centerHeight])))
                        normals.append(SCNVector3(yUp(normal)))
                        // Like GLUT, each patch maps the whole texture once.
                        textureCoordinates.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
                    }
                }

                // A single mirror flips the winding, so swap two corners to keep faces pointing out.
                let isReflection = mirror.x * mirror.y < 0
                for row in 0..<n {
                    for column in 0..<n {
                        let a = UInt16(base + row * (n + 1) + column)
                        let b = a + 1
                        let c = a + UInt16(n + 1)
                        let d = c + 1
                        indices += isReflection ? [a, c, b, b, c, d] : [a, b, c, b, d, c]
                    }
                }
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

    private static func evaluate(_ points: [SIMD3<Float>], _ weightsU: SIMD4<Float>, _ weightsV: SIMD4<Float>) -> SIMD3<Float> {
        var result = SIMD3<Float>(repeating: 0)
        for row in 0..<4 {
            for column in 0..<4 {
                result += points[row * 4 + column] * (weightsV[row] * weightsU[column])
            }
        }
        return result
    }

    private static func bernstein(_ t: Float) -> SIMD4<Float> {
        let s = 1 - t
        return [s * s * s, 3 * t * s * s, 3 * t * t * s, t * t * t]
    }

    private static func bernsteinDerivative(_ t: Float) -> SIMD4<Float> {
        let s = 1 - t
        return [-3 * s * s, 3 * s * s - 6 * t * s, 6 * t * s - 3 * t * t, 3 * t * t]
    }

    private static func derivativeParameter(_ t: Float) -> Float {
        t.clamped(to: 0.01...0.99)
    }

    private static func yUp(_ point: SIMD3<Float>) -> SIMD3<Float> {
        [point.x, point.z, -point.y]
    }
}
