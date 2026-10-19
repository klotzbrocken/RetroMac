import AppKit

/// RetroMac's own menu icons for its own places: a compact Mac with a download arrow for RetroHub
/// and a painter's palette for Themes. Pixel art at 16 × 16, drawn as template images so the menu
/// tints them like any system symbol, in light and dark.
enum MenuPixelIcons {
    static let retroHub = image([
        "................",
        "...##########...",
        "...#........#...",
        "...#.######.#...",
        "...#.##..##.#...",
        "...#.##..##.#...",
        "...#.##..##.#...",
        "...#.#....#.#...",
        "...#.##..##.#...",
        "...#.######.#...",
        "...#........#...",
        "...#...####.#...",
        "...#........#...",
        "...##########...",
        "....########....",
        "................"], name: "RetroHub")

    static let themes = image([
        "................",
        "....#######.....",
        "..###########...",
        ".####..########.",
        ".####..##..####.",
        "#########..#####",
        "#..#############",
        "#..#########....",
        "###########.....",
        "###########.....",
        "##..#########...",
        "##..###########.",
        ".#########..###.",
        ".#########..##..",
        "..#########.....",
        "....######......"], name: "Themes")

    private static func image(_ rows: [String], name: String) -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, c) in row.enumerated() where c == "#" {
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = name
        return img
    }
}
