import SceneKit
import simd

/// How far along the morph the object is; every part runs from 0 (plain shape) to 1.
struct MorphState {
    /// Faces swelling into balloon-like petals.
    var petals: Float = 0
    /// Spikes shooting out of the corners.
    var spikes: Float = 0
    /// Blending onto a ball.
    var roundness: Float = 0
}

/// One curved piece of a shape's surface, parameterised over (u, v) in 0...1.
struct Patch {
    var position: (Float, Float) -> SIMD3<Float>
    /// Away from the solid, for orienting the patch (and for bead blooming).
    var outward: (Float, Float) -> SIMD3<Float>
    /// 1 in the middle of the patch, 0 on its edges (used by bead blooming).
    var centeredness: (Float, Float) -> Float
}

/// How a shape blooms.
enum BloomStyle {
    /// The shape shrinks into a core while each face swells into a ball-shaped petal and each corner
    /// shoots out a spike. Every point moves along its ray from the centre, so patches stay joined.
    case flower(petals: [SIMD3<Float>], spikes: [SIMD3<Float>])
    /// Each patch swells in its middle, like beads on a string. For the spring.
    case beads(height: Float)
}

/// A shape as a set of patches, each tessellated into its own grid of vertices so that every
/// patch can have its own colour.
///
/// Every morph cycle is the same, so each morph state's finished geometry is built once and kept:
/// after the first cycle, drawing a frame just picks an existing geometry, already on the GPU.
final class ShapeMesh {
    /// Radius of the ball the shape morphs into, and roughly the size of every shape at rest.
    static let ballRadius: Float = 0.9
    /// How much the shape shrinks into its core while blooming, which pinches the petals' necks.
    private static let coreShrink: Float = 0.45
    /// A full-grown petal is a ball of this radius, centred this far out.
    private static let petalRadius: Float = 0.58
    private static let petalDistance: Float = 0.9
    private static let spikeReach: Float = 2
    /// Angle from a spike's axis to its edge at the base, in radians.
    private static let spikeWidth: Float = 0.22
    private static let spikeWidthCosine = cos(spikeWidth)
    /// How softly petals and spikes blend into the core, instead of meeting at sharp creases.
    private static let blendWidth: Float = 0.12

    let patches: [Patch]
    /// Grid cells along each side of a patch.
    let resolution: Int
    /// Whether the shape morphs into a ball; the spring would just tangle itself up.
    let canRound: Bool
    /// Bounding radius at full bloom, for keeping the object on screen.
    let maxRadius: Float

    private let style: BloomStyle
    private let grids: [Grid]
    private let elements: [SCNGeometryElement]
    /// Finished geometry by morph state (rounded, so pauses in the cycle share one).
    private var cache: [SIMD3<Int32>: SCNGeometry] = [:]

    /// A patch sampled on its (n + 1)² vertices plus a one-vertex border. The border lets normals
    /// along a patch's edge be worked out the same way as inside it.
    private struct Grid {
        var base: [SIMD3<Float>] = []
        var directions: [SIMD3<Float>] = []
        var lengths: [Float] = []
        var outward: [SIMD3<Float>] = []
        var centeredness: [Float] = []
        /// (u, v) run clockwise seen from outside, so normals and winding flip.
        var isFlipped = false
    }

    init(shape: FlowerBoxShape) {
        (patches, style, canRound) = Self.definition(of: shape)
        // Coarse, like the original. Shapes made of more, smaller patches need fewer cells per patch.
        switch shape {
        case .cube, .tetrahedron, .pyramid: resolution = 16
        case .cylinder: resolution = 10
        case .spring: resolution = 8
        }

        let n = resolution
        var grids: [Grid] = []
        var elements: [SCNGeometryElement] = []
        var restRadius: Float = 0
        for (index, patch) in patches.enumerated() {
            var grid = Grid()
            for row in -1...(n + 1) {
                for column in -1...(n + 1) {
                    let u = Float(column) / Float(n)
                    let v = Float(row) / Float(n)
                    let point = patch.position(u, v)
                    let length = simd_length(point)
                    grid.base.append(point)
                    grid.lengths.append(length)
                    grid.directions.append(length > 0 ? point / length : patch.outward(u, v))
                    grid.outward.append(patch.outward(u, v))
                    grid.centeredness.append(patch.centeredness(u, v))
                    if (0...n).contains(row), (0...n).contains(column) {
                        restRadius = max(restRadius, length)
                    }
                }
            }
            let tangentU = patch.position(0.51, 0.5) - patch.position(0.49, 0.5)
            let tangentV = patch.position(0.5, 0.51) - patch.position(0.5, 0.49)
            grid.isFlipped = simd_dot(simd_cross(tangentU, tangentV), patch.outward(0.5, 0.5)) < 0
            grids.append(grid)

            let base = index * (n + 1) * (n + 1)
            var indices: [UInt16] = []
            for row in 0..<n {
                for column in 0..<n {
                    let a = UInt16(base + row * (n + 1) + column)
                    let b = a + 1
                    let c = a + UInt16(n + 1)
                    let d = c + 1
                    indices += grid.isFlipped ? [a, c, b, b, c, d] : [a, b, c, b, d, c]
                }
            }
            elements.append(SCNGeometryElement(indices: indices, primitiveType: .triangles))
        }
        self.grids = grids
        self.elements = elements

        switch style {
        case .flower(let petals, let spikes):
            var reach = max(restRadius, Self.ballRadius)
            if !petals.isEmpty { reach = max(reach, Self.petalDistance + Self.petalRadius) }
            if !spikes.isEmpty { reach = max(reach, Self.spikeReach) }
            maxRadius = reach
        case .beads(let height):
            maxRadius = restRadius + height
        }
    }

    /// The geometry for `state`, built the first time it's needed. Its materials are shared, so
    /// colour changes reach every cached geometry.
    func geometry(for state: MorphState, materials: [SCNMaterial]) -> SCNGeometry {
        let key = SIMD3<Int32>(SIMD3(state.petals, state.spikes, state.roundness) * 10_000, rounding: .toNearestOrEven)
        if let geometry = cache[key] {
            return geometry
        }
        let geometry = makeGeometry(for: state)
        geometry.materials = materials
        cache[key] = geometry
        return geometry
    }

    private func makeGeometry(for state: MorphState) -> SCNGeometry {
        let n = resolution
        let width = n + 3
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity(grids.count * (n + 1) * (n + 1))
        normals.reserveCapacity(positions.capacity)
        for grid in grids {
            let points = grid.base.indices.map { point(grid, $0, state) }
            func normal(at index: Int) -> SIMD3<Float>? {
                let cross = simd_cross(points[index + 1] - points[index - 1], points[index + width] - points[index - width])
                let length = simd_length(cross)
                return length > 1e-10 ? cross / length : nil
            }
            let sign: Float = grid.isFlipped ? -1 : 1
            for row in 1...(n + 1) {
                for column in 1...(n + 1) {
                    let index = row * width + column
                    positions.append(points[index])
                    // At a triangle's tip a whole row collapses into one point: borrow the next vertex's normal.
                    let normal = normal(at: index) ?? normal(at: index + 1) ?? normal(at: index + width) ?? grid.directions[index]
                    normals.append(normal * sign)
                }
            }
        }
        return SCNGeometry(sources: [Self.source(positions, .vertex), Self.source(normals, .normal)], elements: elements)
    }

    private func point(_ grid: Grid, _ index: Int, _ state: MorphState) -> SIMD3<Float> {
        var point = grid.base[index]
        let bloom = max(state.petals, state.spikes)
        if bloom > 0 {
            switch style {
            case .flower(let petals, let spikes):
                // The surface is the shrunken core with the petals and spikes blended onto it.
                let direction = grid.directions[index]
                var radius = grid.lengths[index] * (1 - Self.coreShrink * bloom)
                if state.petals > 0 {
                    for axis in petals {
                        radius = Self.smoothMax(radius, Self.petalRadius(along: direction, axis: axis, growth: state.petals))
                    }
                }
                if state.spikes > 0 {
                    for axis in spikes {
                        radius = Self.smoothMax(radius, Self.spikeRadius(along: direction, axis: axis, growth: state.spikes))
                    }
                }
                point = direction * radius
            case .beads(let height):
                point += grid.outward[index] * height * bloom * grid.centeredness[index]
            }
        }
        if canRound, state.roundness > 0 {
            point += (grid.directions[index] * Self.ballRadius - point) * state.roundness
        }
        return point
    }

    /// The larger of the two, rounded off where they're close, so shapes merge with a soft fillet.
    private static func smoothMax(_ a: Float, _ b: Float) -> Float {
        let h = max(blendWidth - abs(a - b), 0) / blendWidth
        return max(a, b) + h * h * blendWidth / 4
    }

    /// Where the ray along `direction` leaves a petal: a ball on `axis` that grows out of the core.
    /// 0 if the ray misses it.
    private static func petalRadius(along direction: SIMD3<Float>, axis: SIMD3<Float>, growth: Float) -> Float {
        let cosine = simd_dot(direction, axis)
        guard cosine > 0 else { return 0 }
        let distance = petalDistance * (0.47 + 0.53 * growth)
        let radius = petalRadius * growth
        let discriminant = radius * radius - distance * distance * (1 - cosine * cosine)
        guard discriminant > 0 else { return 0 }
        return distance * cosine + discriminant.squareRoot()
    }

    /// A thin cone along `axis`, longer the more it has grown. 0 outside it.
    private static func spikeRadius(along direction: SIMD3<Float>, axis: SIMD3<Float>, growth: Float) -> Float {
        let cosine = simd_dot(direction, axis)
        guard cosine > spikeWidthCosine else { return 0 }
        return spikeReach * growth * (1 - acos(min(1, cosine)) / spikeWidth)
    }

    private static func source(_ vectors: [SIMD3<Float>], _ semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        let stride = MemoryLayout<SIMD3<Float>>.stride
        return SCNGeometrySource(
            data: vectors.withUnsafeBytes { Data($0) }, semantic: semantic, vectorCount: vectors.count,
            usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: stride
        )
    }
}

// MARK: - Shapes

extension ShapeMesh {
    private static func definition(of shape: FlowerBoxShape) -> ([Patch], BloomStyle, canRound: Bool) {
        switch shape {
        case .cube:
            let half: Float = 0.62
            let axes: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
            var patches: [Patch] = []
            for (index, axis) in axes.enumerated() {
                for normal in [axis, -axis] {
                    let edgeU = axes[(index + 1) % 3] * (2 * half)
                    let edgeV = axes[(index + 2) % 3] * (2 * half)
                    patches.append(square(center: normal * half, edgeU: edgeU, edgeV: edgeV, outward: normal))
                }
            }
            var corners: [SIMD3<Float>] = []
            for x in [-1, 1] as [Float] {
                for y in [-1, 1] as [Float] {
                    for z in [-1, 1] as [Float] {
                        corners.append(simd_normalize([x, y, z]))
                    }
                }
            }
            return (patches, .flower(petals: axes + axes.map { -$0 }, spikes: corners), true)

        case .tetrahedron:
            let s: Float = 0.62
            let corners: [SIMD3<Float>] = [[s, s, s], [s, -s, -s], [-s, s, -s], [-s, -s, s]]
            let patches = [(0, 1, 2), (0, 3, 1), (0, 2, 3), (1, 3, 2)].map { triangle(corners[$0], corners[$1], corners[$2]) }
            // Each face points away from the corner opposite it.
            let directions = corners.map(simd_normalize)
            return (patches, .flower(petals: directions.map { -$0 }, spikes: directions), true)

        case .pyramid:
            let half: Float = 0.7
            let bottom: Float = -0.5
            let apex: SIMD3<Float> = [0, 0.85, 0]
            let base: [SIMD3<Float>] = [[-half, bottom, -half], [half, bottom, -half], [half, bottom, half], [-half, bottom, half]]
            var patches = (0..<4).map { triangle(apex, base[$0], base[($0 + 1) % 4]) }
            patches.append(square(center: [0, bottom, 0], edgeU: [2 * half, 0, 0], edgeV: [0, 0, 2 * half], outward: [0, -1, 0]))
            var petals = (0..<4).map { simd_normalize(apex + base[$0] + base[($0 + 1) % 4]) }
            petals.append([0, -1, 0])
            return (patches, .flower(petals: petals, spikes: ([apex] + base).map(simd_normalize)), true)

        case .cylinder:
            return cylinder()

        case .spring:
            return (spring(), .beads(height: 0.1), false)
        }
    }

    private static func cylinder() -> ([Patch], BloomStyle, canRound: Bool) {
        let radius: Float = 0.62
        let height: Float = 1.3
        let panels = 6
        var patches: [Patch] = []
        var petals: [SIMD3<Float>] = [[0, 1, 0], [0, -1, 0]]
        var spikes: [SIMD3<Float>] = []
        for panel in 0..<panels {
            let angle = { (u: Float) in (Float(panel) + u) * 2 * .pi / Float(panels) }
            patches.append(Patch(
                position: { u, v in [radius * cos(angle(u)), (v - 0.5) * height, radius * sin(angle(u))] },
                outward: { u, _ in [cos(angle(u)), 0, sin(angle(u))] },
                centeredness: { u, v in squareCenteredness(u, v) }
            ))
            for y in [height / 2, -height / 2] {
                let center: SIMD3<Float> = [0, y, 0]
                patches.append(Patch(
                    position: { u, v in center + u * [radius * cos(angle(v)), 0, radius * sin(angle(v))] },
                    outward: { _, _ in [0, y > 0 ? 1 : -1, 0] },
                    centeredness: { u, v in triangleCenteredness(u, v) }
                ))
                spikes.append(simd_normalize([radius * cos(angle(0)), y, radius * sin(angle(0))]))
            }
            petals.append([cos(angle(0.5)), 0, sin(angle(0.5))])
        }
        return (patches, .flower(petals: petals, spikes: spikes), true)
    }

    private static func spring() -> [Patch] {
        let coilRadius: Float = 0.6
        let height: Float = 1.5
        let turns: Float = 2.5
        let tubeRadius: Float = 0.16
        let segments = 20

        // The coil's centre line and a frame around it.
        func center(_ s: Float) -> SIMD3<Float> {
            let angle = s * turns * 2 * .pi
            return [coilRadius * cos(angle), (s - 0.5) * height, coilRadius * sin(angle)]
        }
        func frame(_ s: Float) -> (tangent: SIMD3<Float>, normal: SIMD3<Float>, binormal: SIMD3<Float>) {
            let tangent = simd_normalize(center(s + 0.001) - center(s - 0.001))
            let angle = s * turns * 2 * .pi
            let radial: SIMD3<Float> = [cos(angle), 0, sin(angle)]
            let normal = simd_normalize(radial - simd_dot(radial, tangent) * tangent)
            return (tangent, normal, simd_cross(tangent, normal))
        }
        func around(_ s: Float, _ v: Float) -> SIMD3<Float> {
            let f = frame(s)
            let angle = v * 2 * .pi
            return cos(angle) * f.normal + sin(angle) * f.binormal
        }

        var patches = (0..<segments).map { segment -> Patch in
            let s = { (u: Float) in (Float(segment) + u) / Float(segments) }
            return Patch(
                position: { u, v in center(s(u)) + tubeRadius * around(s(u), v) },
                outward: { u, v in around(s(u), v) },
                centeredness: { u, _ in sin(.pi * u.clamped(to: 0...1)) }
            )
        }
        // Close both ends of the tube.
        for (s, direction) in [(Float(0), Float(-1)), (Float(1), Float(1))] {
            patches.append(Patch(
                position: { u, v in center(s) + u * tubeRadius * around(s, v) },
                outward: { _, _ in direction * frame(s).tangent },
                centeredness: { _, _ in 0 }
            ))
        }
        return patches
    }

    /// A parallelogram face around `center`.
    private static func square(center: SIMD3<Float>, edgeU: SIMD3<Float>, edgeV: SIMD3<Float>, outward: SIMD3<Float>) -> Patch {
        Patch(
            position: { u, v in center + (u - 0.5) * edgeU + (v - 0.5) * edgeV },
            outward: { _, _ in outward },
            centeredness: { u, v in squareCenteredness(u, v) }
        )
    }

    /// A flat triangle; u runs from `a` to the edge `b`–`c`, v along that edge.
    private static func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Patch {
        var normal = simd_normalize(simd_cross(b - a, c - a))
        if simd_dot(normal, a + b + c) < 0 {
            normal = -normal
        }
        return Patch(
            position: { u, v in a + u * (b + v * (c - b) - a) },
            outward: { [normal] _, _ in normal },
            centeredness: { u, v in triangleCenteredness(u, v) }
        )
    }

    private static func squareCenteredness(_ u: Float, _ v: Float) -> Float {
        sin(.pi * u.clamped(to: 0...1)) * sin(.pi * v.clamped(to: 0...1))
    }

    /// From barycentric coordinates, scaled to 1 at the triangle's centre.
    private static func triangleCenteredness(_ u: Float, _ v: Float) -> Float {
        let u = u.clamped(to: 0...1)
        let v = v.clamped(to: 0...1)
        return 27 * (1 - u) * (u * (1 - v)) * (u * v)
    }
}
