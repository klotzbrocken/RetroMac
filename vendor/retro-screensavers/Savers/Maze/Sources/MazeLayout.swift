import simd

/// A compass direction in the maze. North is towards -z in the scene, east towards +x.
enum Heading: Int, CaseIterable {
    case north, east, south, west

    var offset: SIMD2<Int> {
        switch self {
        case .north: return [0, -1]
        case .east: return [1, 0]
        case .south: return [0, 1]
        case .west: return [-1, 0]
        }
    }

    var right: Heading { Heading(rawValue: (rawValue + 1) % 4)! }
    var left: Heading { Heading(rawValue: (rawValue + 3) % 4)! }
    var back: Heading { Heading(rawValue: (rawValue + 2) % 4)! }

    /// Rotation about Y that turns something facing north (-z) to face this way.
    var yaw: Float {
        switch self {
        case .north: return 0
        case .east: return -.pi / 2
        case .south: return .pi
        case .west: return .pi / 2
        }
    }
}

/// A perfect maze (exactly one path between any two cells) on a square grid, carved by a
/// randomised depth-first search.
struct MazeLayout {
    let size: Int
    let start: SIMD2<Int>
    let finish: SIMD2<Int>
    /// Whether each cell has a passage in each heading, indexed [cell][heading].
    private var passages: [[Bool]]

    init(size: Int, rng: inout SplitMix64) {
        self.size = size
        passages = Array(repeating: Array(repeating: false, count: 4), count: size * size)

        var visited = Array(repeating: false, count: size * size)
        let first = SIMD2(Int.random(in: 0..<size, using: &rng), Int.random(in: 0..<size, using: &rng))
        var stack = [first]
        visited[first.y * size + first.x] = true
        while let cell = stack.last {
            let unvisited = Heading.allCases.filter { heading in
                let next = cell &+ heading.offset
                return Self.contains(next, size: size) && !visited[next.y * size + next.x]
            }
            guard let heading = unvisited.randomElement(using: &rng) else {
                stack.removeLast()
                continue
            }
            let next = cell &+ heading.offset
            passages[cell.y * size + cell.x][heading.rawValue] = true
            passages[next.y * size + next.x][heading.back.rawValue] = true
            visited[next.y * size + next.x] = true
            stack.append(next)
        }

        // Start in a corner and finish as far away as the maze allows, so every walk is a long one.
        let corner = SIMD2(Bool.random(using: &rng) ? 0 : size - 1, Bool.random(using: &rng) ? 0 : size - 1)
        start = corner
        let distances = Self.distances(from: corner, size: size, passages: passages)
        let farthest = distances.indices.max { distances[$0] < distances[$1] }!
        finish = SIMD2(farthest % size, farthest / size)
    }

    func isOpen(_ cell: SIMD2<Int>, _ heading: Heading) -> Bool {
        Self.contains(cell, size: size) && passages[cell.y * size + cell.x][heading.rawValue]
    }

    /// Which way to go next from `cell` when facing `heading`, keeping a hand on the right wall.
    /// That reaches every cell of a perfect maze, dead ends included, like the original's walk.
    func rightHandTurn(at cell: SIMD2<Int>, facing heading: Heading) -> Heading {
        for candidate in [heading.right, heading, heading.left, heading.back] where isOpen(cell, candidate) {
            return candidate
        }
        return heading.back
    }

    func openHeadings(at cell: SIMD2<Int>) -> [Heading] {
        Heading.allCases.filter { isOpen(cell, $0) }
    }

    private static func contains(_ cell: SIMD2<Int>, size: Int) -> Bool {
        cell.x >= 0 && cell.y >= 0 && cell.x < size && cell.y < size
    }

    private static func distances(from start: SIMD2<Int>, size: Int, passages: [[Bool]]) -> [Int] {
        var distances = Array(repeating: Int.max, count: size * size)
        distances[start.y * size + start.x] = 0
        var queue = [start]
        var head = 0
        while head < queue.count {
            let cell = queue[head]
            head += 1
            for heading in Heading.allCases where passages[cell.y * size + cell.x][heading.rawValue] {
                let next = cell &+ heading.offset
                let index = next.y * size + next.x
                if distances[index] == .max {
                    distances[index] = distances[cell.y * size + cell.x] + 1
                    queue.append(next)
                }
            }
        }
        return distances
    }
}
