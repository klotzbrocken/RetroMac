import SwiftUI

/// Reusable picker for Lite overlay shaders. Used in Quake sections and ROM rows.
struct LiteShaderPicker: View {
    @Binding var selection: String

    /// All available Lite shader options
    private static let liteShaders: [(name: String, id: String)] = [
        ("CRT Lite", "crt-lite"),
        ("LCD Lite", "lcd-lite"),
        ("LCD Retro Lite", "lcd-retro-lite"),
        ("LCD Sharp Lite", "lcd-sharp-lite"),
        ("LCD Broken Lite", "lcd-broken-lite"),
        ("B&W Lite", "bw-lite"),
        ("Amber Lite", "amber-lite"),
        ("VHS Lite", "vhs-lite"),
        ("Scanlines Lite", "scanlines-lite"),
        ("Film Scratches Lite", "grain-lite"),
    ]

    var body: some View {
        Picker("", selection: $selection) {
            Text("None").tag("none")
            Divider()
            ForEach(Self.liteShaders, id: \.id) { shader in
                Text("⚡ \(shader.name)").tag(shader.id)
            }
        }
        .pickerStyle(.menu)
    }
}
