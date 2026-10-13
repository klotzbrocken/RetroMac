import simd

/// One of the six axis-aligned directions a pipe can travel in.
enum Direction: CaseIterable {
    case right, left, up, down, forward, back

    var offset: SIMD3<Int> {
        switch self {
        case .right: return [1, 0, 0]
        case .left: return [-1, 0, 0]
        case .up: return [0, 1, 0]
        case .down: return [0, -1, 0]
        case .forward: return [0, 0, 1]
        case .back: return [0, 0, -1]
        }
    }

    var vector: SIMD3<Float> { SIMD3<Float>(offset) }

    /// The four directions a pipe can turn into from this one.
    var perpendiculars: [Direction] {
        Direction.allCases.filter { ($0.offset &* offset).wrappedSum() == 0 }
    }
}

/// The 3D lattice pipes grow through. Cells are one unit apart and the grid is centred on the origin.
struct Grid {
    let size: SIMD3<Int>
    private var occupied: [Bool]
    private(set) var occupiedCount = 0

    init(size: SIMD3<Int>) {
        self.size = size
        occupied = Array(repeating: false, count: size.x * size.y * size.z)
    }

    var fillRatio: Double { Double(occupiedCount) / Double(occupied.count) }

    func contains(_ cell: SIMD3<Int>) -> Bool {
        all(cell .>= 0) && all(cell .< size)
    }

    func isFree(_ cell: SIMD3<Int>) -> Bool {
        contains(cell) && !occupied[index(of: cell)]
    }

    mutating func occupy(_ cell: SIMD3<Int>) {
        let i = index(of: cell)
        if !occupied[i] {
            occupied[i] = true
            occupiedCount += 1
        }
    }

    mutating func clear() {
        occupied = Array(repeating: false, count: occupied.count)
        occupiedCount = 0
    }

    func center(of cell: SIMD3<Int>) -> SIMD3<Float> {
        SIMD3<Float>(cell) - (SIMD3<Float>(size) - 1) / 2
    }

    private func index(of cell: SIMD3<Int>) -> Int {
        (cell.z * size.y + cell.y) * size.x + cell.x
    }
}
