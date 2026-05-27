/// Color math and animation utilities.
/// All arithmetic is integer-only for BEAM determinism.
import etui/anim
import etui/style
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// RGB interpolation

/// Linear interpolation between two Rgb colors.
/// For non-Rgb inputs, returns whichever endpoint is closer to t.
pub fn lerp_rgb(
  a: style.Color,
  b: style.Color,
  t: Int,
  max: Int,
) -> style.Color {
  case a, b {
    style.Rgb(r1, g1, b1), style.Rgb(r2, g2, b2) ->
      style.Rgb(
        anim.lerp(r1, r2, t, max),
        anim.lerp(g1, g2, t, max),
        anim.lerp(b1, b2, t, max),
      )
    _, _ ->
      case t * 2 < max {
        True -> a
        False -> b
      }
  }
}

// ─────────────────────────────────────────────────────────────────
// Hue → RGB

/// Convert a hue angle (0–359) to a fully-saturated Rgb color.
/// Implements the HSV→RGB formula with S=1, V=1, integer arithmetic.
pub fn hue_to_rgb(hue: Int) -> style.Color {
  let h = { hue % 360 + 360 } % 360
  let sector = h / 60
  let f = h % 60
  let up = f * 255 / 60
  let dn = { 60 - f } * 255 / 60
  case sector {
    0 -> style.Rgb(255, up, 0)
    1 -> style.Rgb(dn, 255, 0)
    2 -> style.Rgb(0, 255, up)
    3 -> style.Rgb(0, dn, 255)
    4 -> style.Rgb(up, 0, 255)
    _ -> style.Rgb(255, 0, dn)
  }
}

// ─────────────────────────────────────────────────────────────────
// Rainbow

/// Returns an Rgb color that cycles through the full hue spectrum
/// with the given period in frames.
pub fn rainbow(frame: Int, period: Int) -> style.Color {
  let p = int.max(1, period)
  hue_to_rgb(anim.cycle(frame, p) * 360 / p)
}

// ─────────────────────────────────────────────────────────────────
// Gradient

/// Color at integer position `pos` within [0, max] across a list of
/// color stops. Stops are distributed evenly. Lerps between adjacent
/// stops. Requires Rgb stops for smooth blending; non-Rgb stops snap.
pub fn gradient(stops: List(style.Color), pos: Int, max: Int) -> style.Color {
  let n = list.length(stops)
  case n {
    0 -> style.Default
    1 ->
      case stops {
        [c, ..] -> c
        [] -> style.Default
      }
    _ -> {
      let segs = n - 1
      let seg_size = int.max(1, max / segs)
      let seg_idx = int.min(segs - 1, pos / seg_size)
      let seg_pos = pos - seg_idx * seg_size
      lerp_rgb(
        get_nth(stops, seg_idx),
        get_nth(stops, seg_idx + 1),
        seg_pos,
        seg_size,
      )
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Pulse

/// Oscillate an Rgb color between half and full brightness.
/// Use `frame + x * phase_step` for a per-cell wave effect.
/// Non-Rgb colors are returned unchanged.
pub fn pulse(c: style.Color, frame: Int, period: Int) -> style.Color {
  case c {
    style.Rgb(r, g, b) -> {
      let bright = anim.oscillate(128, 255, frame, int.max(1, period))
      style.Rgb(r * bright / 255, g * bright / 255, b * bright / 255)
    }
    _ -> c
  }
}

// ─────────────────────────────────────────────────────────────────
// Darken / brighten

/// Scale all RGB channels by `factor` / 255.
/// factor=255 → unchanged, factor=128 → half brightness.
pub fn scale(c: style.Color, factor: Int) -> style.Color {
  case c {
    style.Rgb(r, g, b) ->
      style.Rgb(r * factor / 255, g * factor / 255, b * factor / 255)
    _ -> c
  }
}

// ─────────────────────────────────────────────────────────────────
// Helpers

fn get_nth(colors: List(style.Color), n: Int) -> style.Color {
  case colors {
    [] -> style.Default
    [c, ..] if n <= 0 -> c
    [_, ..rest] -> get_nth(rest, n - 1)
  }
}
