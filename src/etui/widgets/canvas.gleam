/// Braille canvas widget for high-resolution line charts.
/// Each terminal cell holds a Unicode braille character (U+2800–U+28FF)
/// providing a 2×4 pixel dot-grid per cell. Multiple series are overlaid.
/// Pixel resolution: area.width*2 × area.height*4.
import etui/braille
import etui/buffer
import etui/color
import etui/geometry
import etui/style
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

pub type SeriesFill {
  /// Single solid color for all dots.
  SeriesSolid(c: style.Color)
  /// Left-to-right gradient across the canvas width (in pixels).
  SeriesGradient(stops: List(style.Color))
  /// Per-column rainbow, static.
  SeriesRainbow
  /// Rainbow that rotates hue over time.
  SeriesAnimatedRainbow
}

pub type Series {
  Series(data: List(Int), fill: SeriesFill)
}

pub type Canvas {
  Canvas(
    series: List(Series),
    /// 0 = auto-compute max from all series data.
    max_val: Int,
    bg: style.Color,
    /// Animation period in frames.
    period: Int,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

pub fn canvas_new(series: List(Series)) -> Canvas {
  Canvas(series: series, max_val: 0, bg: style.Default, period: 60)
}

pub fn series_new(data: List(Int)) -> Series {
  Series(data: data, fill: SeriesRainbow)
}

pub fn with_series_fill(s: Series, fill: SeriesFill) -> Series {
  Series(..s, fill: fill)
}

pub fn with_max(c: Canvas, max: Int) -> Canvas {
  Canvas(..c, max_val: int.max(1, max))
}

pub fn with_bg(c: Canvas, bg: style.Color) -> Canvas {
  Canvas(..c, bg: bg)
}

pub fn with_period(c: Canvas, period: Int) -> Canvas {
  Canvas(..c, period: int.max(1, period))
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render canvas into `area`. `frame` drives animated fills.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  c: Canvas,
  frame: Int,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let pw = area.size.width * 2
      let ph = area.size.height * 4
      let max = case c.max_val {
        0 ->
          list.fold(c.series, 1, fn(acc, ser) {
            list.fold(ser.data, acc, int.max)
          })
        m -> m
      }
      let pixels =
        list.index_fold(c.series, braille.new(), fn(px_dict, ser, _) {
          draw_series(px_dict, ser, pw, ph, max, frame, c.period)
        })
      braille.flush(buf, area, pixels, c.bg)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Series drawing

fn draw_series(
  pixels: braille.Pixels,
  ser: Series,
  pw: Int,
  ph: Int,
  max: Int,
  frame: Int,
  period: Int,
) -> braille.Pixels {
  let n = list.length(ser.data)
  case n {
    0 -> pixels
    _ -> {
      let coords = data_to_coords(ser.data, n, pw, ph, max)
      draw_segments(pixels, ser, coords, pw, frame, period)
    }
  }
}

fn data_to_coords(
  data: List(Int),
  n: Int,
  pw: Int,
  ph: Int,
  max: Int,
) -> List(#(Int, Int)) {
  let range = int.max(1, max)
  let max_px = int.max(0, pw - 1)
  let max_py = int.max(0, ph - 1)
  list.index_map(data, fn(val, i) {
    let px = case n <= 1 {
      True -> 0
      False -> i * max_px / { n - 1 }
    }
    let clamped = int.clamp(val, 0, range)
    let py = max_py - clamped * max_py / range
    #(px, py)
  })
}

fn draw_segments(
  pixels: braille.Pixels,
  ser: Series,
  coords: List(#(Int, Int)),
  pw: Int,
  frame: Int,
  period: Int,
) -> braille.Pixels {
  case coords {
    [] -> pixels
    [_] -> pixels
    [p0, p1, ..rest] -> {
      let #(x0, y0) = p0
      let #(x1, y1) = p1
      let pts = bresenham(x0, y0, x1, y1)
      let pixels =
        list.fold(pts, pixels, fn(px_dict, pt) {
          let #(px, py) = pt
          let fg = series_color(ser.fill, px, pw, frame, period)
          braille.put(px_dict, px, py, fg)
        })
      draw_segments(pixels, ser, [p1, ..rest], pw, frame, period)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Bresenham line algorithm

fn bresenham(x0: Int, y0: Int, x1: Int, y1: Int) -> List(#(Int, Int)) {
  let dx = int.absolute_value(x1 - x0)
  let dy = 0 - int.absolute_value(y1 - y0)
  let sx = case x0 < x1 {
    True -> 1
    False -> -1
  }
  let sy = case y0 < y1 {
    True -> 1
    False -> -1
  }
  bresenham_loop(x0, y0, x1, y1, sx, sy, dx, dy, dx + dy, [])
}

fn bresenham_loop(
  x0: Int,
  y0: Int,
  x1: Int,
  y1: Int,
  sx: Int,
  sy: Int,
  dx: Int,
  dy: Int,
  err: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  let acc = [#(x0, y0), ..acc]
  case x0 == x1 && y0 == y1 {
    True -> acc
    False -> {
      let e2 = 2 * err
      let #(err, x0) = case e2 >= dy {
        True -> #(err + dy, x0 + sx)
        False -> #(err, x0)
      }
      let #(err, y0) = case e2 <= dx {
        True -> #(err + dx, y0 + sy)
        False -> #(err, y0)
      }
      bresenham_loop(x0, y0, x1, y1, sx, sy, dx, dy, err, acc)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Color dispatch

fn series_color(
  fill: SeriesFill,
  px: Int,
  pw: Int,
  frame: Int,
  period: Int,
) -> style.Color {
  let p = int.max(1, period)
  let w = int.max(1, pw)
  case fill {
    SeriesSolid(c) -> c
    SeriesGradient(stops) -> color.gradient(stops, px, w - 1)
    SeriesRainbow -> color.hue_to_rgb(px * 360 / w)
    SeriesAnimatedRainbow ->
      color.hue_to_rgb({ px * 360 / w + frame * 360 / p } % 360)
  }
}
