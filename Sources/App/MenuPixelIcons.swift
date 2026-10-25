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

    /// Real bitmaps at 1x and 2x, not a drawing handler: a template image drawn by a handler came
    /// out blank in the status menu, where the menu renders it to tint it.
    private static func image(_ rows: [String], name: String) -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16))
        for scale in [1, 2] {
            let side = 16 * scale
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: side * 4, bitsPerPixel: 32), let p = rep.bitmapData else { continue }
            memset(p, 0, side * side * 4)
            for (y, row) in rows.enumerated() {
                for (x, c) in row.enumerated() where c == "#" {
                    for dy in 0..<scale { for dx in 0..<scale {
                        p[((y * scale + dy) * side + x * scale + dx) * 4 + 3] = 255   // black, opaque
                    } }
                }
            }
            rep.size = NSSize(width: 16, height: 16)
            img.addRepresentation(rep)
        }
        img.isTemplate = true
        img.accessibilityDescription = name
        return img
    }
}
