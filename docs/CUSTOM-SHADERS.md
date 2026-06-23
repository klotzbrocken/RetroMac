# Building a custom shader for RetroMac

RetroMac runs **Metal** shaders. A preset is a single `.metal` file containing one
full-screen fragment pass that RetroMac draws over your captured screen. You import it in
**Settings → Advanced → Presets → Import .metal…**; it then appears under **Shader Presets**
in the menu-bar popover.

> RetroMac does **not** run GLSL / RetroArch `.slang` shaders directly — the built-in CRT
> presets were ported to Metal. See “GLSL / RetroArch” at the bottom.

---

## The contract

A custom `.metal` file is compiled **on its own** (the built-in header is *not* prepended),
so it must be **self-contained**: include `metal_stdlib`, the `VertexOut` and `Uniforms`
structs, a `vertex_main`, and a `fragment_main`. The function names and the binding indices
must match exactly:

- `vertex_main` — vertices at `buffer(0)`, `Uniforms` at `buffer(1)`
- `fragment_main` — `Uniforms` at `buffer(0)`, the screen texture at `texture(0)`, sampler at `sampler(0)`

### `Uniforms` (provided by RetroMac every frame)

| Field | Meaning |
|---|---|
| `outputSize` | `.xy` = output pixels, `.zw` = 1/output |
| `sourceSize` | `.xy` = captured source pixels, `.zw` = 1/source |
| `frameCount` | frame counter — use for animation |
| `intensity` | the menu **Intensity** slider, 0…1 — blend your effect by this |
| `vignetteIntensity` | the menu **Vignette** slider, 0…1 |

---

## Minimal template (copy, then edit `fragment_main`)

```metal
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms {
    float4x4 mvp;
    float4 outputSize;
    float4 sourceSize;
    float4 originalSize;
    float4 finalViewportSize;
    uint   frameCount;
    int    frameDirection;
    float  intensity;
    float  vignetteIntensity;
};

struct VertexData { packed_float2 position; packed_float2 texCoord; };

vertex VertexOut vertex_main(uint vid [[vertex_id]],
                             const device VertexData* vertices [[buffer(0)]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.texCoord = vertices[vid].texCoord;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(0)]],
                              texture2d<float> source [[texture(0)]],
                              sampler s [[sampler(0)]]) {
    float2 uv = in.texCoord;
    float3 original = source.sample(s, uv).rgb;
    float3 color = original;

    // --- your effect here ---
    // Example: simple horizontal scanlines that fade with the Intensity slider.
    float line = 0.5 + 0.5 * sin(uv.y * uniforms.sourceSize.y * M_PI_F);
    color *= 1.0 - (1.0 - line) * 0.25 * uniforms.intensity;

    // Always honour the Intensity slider so 0% = passthrough:
    color = mix(original, color, uniforms.intensity);

    // Preserve the source alpha (needed for the transparent overlay):
    return float4(color, source.sample(s, uv).a);
}
```

That file compiles and runs as-is — import it and pick it from **Shader Presets**.

---

## Tips

- **Respect `intensity`.** End with `mix(original, color, uniforms.intensity)` so the menu
  slider works and `0%` is a clean passthrough.
- **Keep the source alpha** (`source.sample(s, uv).a`) — RetroMac composites the result as a
  transparent overlay; dropping alpha makes the whole screen opaque.
- **Animate** with `uniforms.frameCount` (e.g. `float t = float(uniforms.frameCount) / 60.0;`).
- **Sample neighbours** for blur/bloom using `uniforms.sourceSize.zw` (one texel step).
- **One pass only.** RetroMac runs a single fragment pass — multi-pass effects (separate
  blur passes, feedback buffers) aren’t supported.
- If the shader fails to compile it simply won’t load — check Console for the Metal error.

---

## GLSL / RetroArch `.slang` shaders

These are **not** loaded directly. RetroMac’s overlay engine is Metal-only; the bundled CRT
presets (crt-lottes, crt-geom, …) were hand-ported from their GLSL originals. To use a GLSL
shader you’d translate it to Metal first (see the transpiler notes in the project docs), or
port the fragment stage by hand into the template above.
