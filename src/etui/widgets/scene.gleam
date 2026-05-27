/// 2D geometric scene widget with braille canvas rendering.
/// Supports circle outlines, animated planet orbits, and Mandelbrot fractal.
/// Pixel resolution: area.width*2 × area.height*4 (2×4 dot-grid per cell).
import etui/braille
import etui/buffer
import etui/color
import etui/geometry
import etui/style
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

pub type SceneFill {
  SceneSolid(c: style.Color)
  SceneGradient(stops: List(style.Color))
  SceneRainbow
  SceneAnimatedRainbow
}

pub type Shape {
  /// Circle outline at braille-pixel coords (cx, cy) with radius r.
  CircleOutline(cx: Int, cy: Int, r: Int, fill: SceneFill)
  /// Filled disc at braille-pixel coords (cx, cy) with radius r.
  Disc(cx: Int, cy: Int, r: Int, fill: SceneFill)
  /// Planet: disc orbiting (cx, cy) at orbit_r, animated by frame/period.
  Planet(
    cx: Int,
    cy: Int,
    orbit_r: Int,
    dot_r: Int,
    fill: SceneFill,
    period: Int,
  )
  /// Mandelbrot set (fills entire canvas area).
  Mandelbrot(max_iter: Int)
}

pub type Scene {
  Scene(shapes: List(Shape), bg: style.Color)
}

// ─────────────────────────────────────────────────────────────────
// Constructors

pub fn scene_new(shapes: List(Shape)) -> Scene {
  Scene(shapes: shapes, bg: style.Default)
}

pub fn with_bg(s: Scene, bg: style.Color) -> Scene {
  Scene(..s, bg: bg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render scene into `area`. `frame` drives animated shapes.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  scene: Scene,
  frame: Int,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let pw = area.size.width * 2
      let ph = area.size.height * 4
      let pixels =
        list.fold(scene.shapes, braille.new(), fn(px_dict, shape) {
          render_shape(px_dict, shape, pw, ph, frame)
        })
      braille.flush(buf, area, pixels, scene.bg)
    }
  }
}

fn render_shape(
  pixels: braille.Pixels,
  shape: Shape,
  pw: Int,
  ph: Int,
  frame: Int,
) -> braille.Pixels {
  case shape {
    CircleOutline(cx, cy, r, fill) ->
      draw_circle_outline(pixels, cx, cy, r, fill, pw, ph, frame, 60)
    Disc(cx, cy, r, fill) ->
      draw_disc(pixels, cx, cy, r, fill, pw, ph, frame, 60)
    Planet(cx, cy, orbit_r, dot_r, fill, period) ->
      draw_planet(pixels, cx, cy, orbit_r, dot_r, fill, pw, ph, frame, period)
    Mandelbrot(max_iter) -> draw_mandelbrot(pixels, pw, ph, max_iter)
  }
}

// ─────────────────────────────────────────────────────────────────
// Circle outline, Bresenham midpoint algorithm

fn draw_circle_outline(
  pixels: braille.Pixels,
  cx: Int,
  cy: Int,
  r: Int,
  fill: SceneFill,
  pw: Int,
  ph: Int,
  frame: Int,
  period: Int,
) -> braille.Pixels {
  let pts = circle_outline_pts(cx, cy, r)
  let n = list.length(pts)
  list.index_fold(pts, pixels, fn(px_dict, pt, i) {
    let #(bx, by) = pt
    case bx >= 0 && by >= 0 && bx < pw && by < ph {
      False -> px_dict
      True -> {
        let fg = scene_color(fill, i, n, frame, period)
        braille.put(px_dict, bx, by, fg)
      }
    }
  })
}

fn circle_outline_pts(cx: Int, cy: Int, r: Int) -> List(#(Int, Int)) {
  case r <= 0 {
    True -> [#(cx, cy)]
    False -> midpoint_loop(cx, cy, 0, r, 1 - r, [])
  }
}

fn midpoint_loop(
  cx: Int,
  cy: Int,
  y: Int,
  x: Int,
  d: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case y > x {
    True -> acc
    False -> {
      let pts = [
        #(cx + x, cy + y),
        #(cx - x, cy + y),
        #(cx + x, cy - y),
        #(cx - x, cy - y),
        #(cx + y, cy + x),
        #(cx - y, cy + x),
        #(cx + y, cy - x),
        #(cx - y, cy - x),
      ]
      let acc = list.append(acc, pts)
      let y = y + 1
      let #(x, d) = case d < 0 {
        True -> #(x, d + 2 * y + 1)
        False -> #(x - 1, d + 2 * { y - x } + 1)
      }
      midpoint_loop(cx, cy, y, x, d, acc)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Filled disc

fn draw_disc(
  pixels: braille.Pixels,
  cx: Int,
  cy: Int,
  r: Int,
  fill: SceneFill,
  pw: Int,
  ph: Int,
  frame: Int,
  period: Int,
) -> braille.Pixels {
  disc_dx_loop(pixels, cx, cy, r, fill, pw, ph, frame, period, 0 - r)
}

fn disc_dx_loop(
  pixels: braille.Pixels,
  cx: Int,
  cy: Int,
  r: Int,
  fill: SceneFill,
  pw: Int,
  ph: Int,
  frame: Int,
  period: Int,
  dx: Int,
) -> braille.Pixels {
  case dx > r {
    True -> pixels
    False -> {
      let pixels =
        disc_dy_loop(pixels, cx, cy, r, fill, pw, ph, frame, period, dx, 0 - r)
      disc_dx_loop(pixels, cx, cy, r, fill, pw, ph, frame, period, dx + 1)
    }
  }
}

fn disc_dy_loop(
  pixels: braille.Pixels,
  cx: Int,
  cy: Int,
  r: Int,
  fill: SceneFill,
  pw: Int,
  ph: Int,
  frame: Int,
  period: Int,
  dx: Int,
  dy: Int,
) -> braille.Pixels {
  case dy > r {
    True -> pixels
    False -> {
      let pixels = case dx * dx + dy * dy <= r * r {
        False -> pixels
        True -> {
          let bx = cx + dx
          let by = cy + dy
          case bx >= 0 && by >= 0 && bx < pw && by < ph {
            False -> pixels
            True -> {
              let fg = scene_color(fill, bx, pw, frame, period)
              braille.put(pixels, bx, by, fg)
            }
          }
        }
      }
      disc_dy_loop(pixels, cx, cy, r, fill, pw, ph, frame, period, dx, dy + 1)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Planet orbit

fn draw_planet(
  pixels: braille.Pixels,
  cx: Int,
  cy: Int,
  orbit_r: Int,
  dot_r: Int,
  fill: SceneFill,
  pw: Int,
  ph: Int,
  frame: Int,
  period: Int,
) -> braille.Pixels {
  let #(px, py) = orbit_position(cx, cy, orbit_r, frame, period)
  draw_disc(pixels, px, py, dot_r, fill, pw, ph, frame, period)
}

/// 32-step integer orbit using precomputed cos/sin × 256.
fn orbit_position(
  cx: Int,
  cy: Int,
  r: Int,
  frame: Int,
  period: Int,
) -> #(Int, Int) {
  let step = { frame * 32 / int.max(1, period) } % 32
  let #(c256, s256) = cos_sin_256(step)
  #(cx + r * c256 / 256, cy + r * s256 / 256)
}

fn cos_sin_256(step: Int) -> #(Int, Int) {
  case step % 32 {
    0 -> #(256, 0)
    1 -> #(251, 50)
    2 -> #(236, 98)
    3 -> #(213, 142)
    4 -> #(181, 181)
    5 -> #(142, 213)
    6 -> #(98, 236)
    7 -> #(50, 251)
    8 -> #(0, 256)
    9 -> #(-50, 251)
    10 -> #(-98, 236)
    11 -> #(-142, 213)
    12 -> #(-181, 181)
    13 -> #(-213, 142)
    14 -> #(-236, 98)
    15 -> #(-251, 50)
    16 -> #(-256, 0)
    17 -> #(-251, -50)
    18 -> #(-236, -98)
    19 -> #(-213, -142)
    20 -> #(-181, -181)
    21 -> #(-142, -213)
    22 -> #(-98, -236)
    23 -> #(-50, -251)
    24 -> #(0, -256)
    25 -> #(50, -251)
    26 -> #(98, -236)
    27 -> #(142, -213)
    28 -> #(181, -181)
    29 -> #(213, -142)
    30 -> #(236, -98)
    _ -> #(251, -50)
  }
}

// ─────────────────────────────────────────────────────────────────
// Mandelbrot fractal, fixed-point scale 1024

fn draw_mandelbrot(
  pixels: braille.Pixels,
  pw: Int,
  ph: Int,
  max_iter: Int,
) -> braille.Pixels {
  // Map braille pixel space onto complex plane:
  //   x ∈ [0, pw-1] → real ∈ [-2.5, 1.0]  (range 3.5 → fixed: -2560..1024 / 1024)
  //   y ∈ [0, ph-1] → imag ∈ [1.25, -1.25] (range 2.5, y inverted)
  let pw1 = int.max(1, pw - 1)
  let ph1 = int.max(1, ph - 1)
  mandelbrot_rows(pixels, pw, ph, pw1, ph1, max_iter, 0)
}

fn mandelbrot_rows(
  pixels: braille.Pixels,
  pw: Int,
  ph: Int,
  pw1: Int,
  ph1: Int,
  max_iter: Int,
  by: Int,
) -> braille.Pixels {
  case by >= ph {
    True -> pixels
    False -> {
      // ci: imag part in fixed-point × 1024. y=0 → top → +1.25 → 1280
      let ci = 1280 - by * 2560 / ph1
      let pixels = mandelbrot_cols(pixels, pw, pw1, max_iter, by, ci, 0)
      mandelbrot_rows(pixels, pw, ph, pw1, ph1, max_iter, by + 1)
    }
  }
}

fn mandelbrot_cols(
  pixels: braille.Pixels,
  pw: Int,
  pw1: Int,
  max_iter: Int,
  by: Int,
  ci: Int,
  bx: Int,
) -> braille.Pixels {
  case bx >= pw {
    True -> pixels
    False -> {
      // cr: real part in fixed-point × 1024. x=0 → -2.5 → -2560
      let cr = -2560 + bx * 3584 / pw1
      let iter = mandelbrot_iter(cr, ci, 0, 0, 0, max_iter)
      let pixels = case iter >= max_iter {
        True -> pixels
        False -> {
          let hue = iter * 300 / max_iter
          let fg = color.hue_to_rgb(hue)
          braille.put(pixels, bx, by, fg)
        }
      }
      mandelbrot_cols(pixels, pw, pw1, max_iter, by, ci, bx + 1)
    }
  }
}

fn mandelbrot_iter(
  cr: Int,
  ci: Int,
  zr: Int,
  zi: Int,
  iter: Int,
  max_iter: Int,
) -> Int {
  case iter >= max_iter {
    True -> iter
    False -> {
      // Fixed-point: zr2 = zr^2/1024, escape when zr2+zi2 > 4096 (=4×1024)
      let zr2 = zr * zr / 1024
      let zi2 = zi * zi / 1024
      case zr2 + zi2 > 4096 {
        True -> iter
        False ->
          mandelbrot_iter(
            cr,
            ci,
            zr2 - zi2 + cr,
            2 * zr * zi / 1024 + ci,
            iter + 1,
            max_iter,
          )
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Color dispatch

fn scene_color(
  fill: SceneFill,
  px: Int,
  pw: Int,
  frame: Int,
  period: Int,
) -> style.Color {
  let p = int.max(1, period)
  let w = int.max(1, pw)
  case fill {
    SceneSolid(c) -> c
    SceneGradient(stops) -> color.gradient(stops, px, w - 1)
    SceneRainbow -> color.hue_to_rgb(px * 360 / w)
    SceneAnimatedRainbow ->
      color.hue_to_rgb({ px * 360 / w + frame * 360 / p } % 360)
  }
}
