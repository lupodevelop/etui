/// Sparkline: single-row bar chart using Unicode block characters.
/// Each data point maps to one of ▁▂▃▄▅▆▇█ based on its value vs max.
/// Supports static or animated gradient fill per column.
import etui/buffer
import etui/color
import etui/geometry
import etui/style
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

pub type SparkFill {
  /// Static left-to-right gradient across color stops.
  SparkGradient(stops: List(style.Color))
  /// Gradient that scrolls left over time.
  SparkAnimated(stops: List(style.Color))
  /// Static full-spectrum rainbow.
  SparkRainbow
  /// Rainbow that rotates hue over time.
  SparkAnimatedRainbow
  /// Single solid color.
  SparkSolid(c: style.Color)
}

pub type Sparkline {
  Sparkline(
    data: List(Int),
    /// Expected maximum value. 0 = auto-compute from data.
    max_val: Int,
    fill: SparkFill,
    bg: style.Color,
    modifier: style.Modifier,
    /// Animation period in frames (for animated fills).
    period: Int,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

pub fn sparkline_new(data: List(Int)) -> Sparkline {
  Sparkline(
    data: data,
    max_val: 0,
    fill: SparkGradient([style.Rgb(0, 180, 255), style.Rgb(0, 255, 180)]),
    bg: style.Default,
    modifier: style.none(),
    period: 60,
  )
}

pub fn with_fill(s: Sparkline, fill: SparkFill) -> Sparkline {
  Sparkline(..s, fill: fill)
}

pub fn with_max(s: Sparkline, max: Int) -> Sparkline {
  Sparkline(..s, max_val: max)
}

pub fn with_bg(s: Sparkline, bg: style.Color) -> Sparkline {
  Sparkline(..s, bg: bg)
}

pub fn with_period(s: Sparkline, period: Int) -> Sparkline {
  Sparkline(..s, period: int.max(1, period))
}

pub fn with_modifier(s: Sparkline, m: style.Modifier) -> Sparkline {
  Sparkline(..s, modifier: m)
}

pub fn with_style(s: Sparkline, st: style.Style) -> Sparkline {
  Sparkline(..s, bg: st.bg, modifier: st.modifier)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the sparkline. `frame` drives animated fills.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  s: Sparkline,
  frame: Int,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let max = case s.max_val {
        0 -> list.fold(s.data, 1, int.max)
        m -> int.max(1, m)
      }
      render_cols(buf, area, s, s.data, 0, area.size.width, max, frame)
    }
  }
}

fn render_cols(
  buf: buffer.Buffer,
  area: geometry.Rect,
  s: Sparkline,
  data: List(Int),
  x: Int,
  width: Int,
  max: Int,
  frame: Int,
) -> buffer.Buffer {
  case x >= width {
    True -> buf
    False -> {
      let val = case data {
        [v, ..] -> v
        [] -> 0
      }
      let rest = case data {
        [_, ..r] -> r
        [] -> []
      }
      let level = int.min(8, val * 8 / int.max(1, max))
      let ch = bar_char(level)
      let fg = cell_color(s.fill, x, width, frame, s.period)
      let pos = geometry.Position(x: area.position.x + x, y: area.position.y)
      let buf2 = buffer.set_string(buf, pos, ch, fg, s.bg, s.modifier)
      render_cols(buf2, area, s, rest, x + 1, width, max, frame)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Helpers

fn bar_char(level: Int) -> String {
  case level {
    0 -> " "
    1 -> "▁"
    2 -> "▂"
    3 -> "▃"
    4 -> "▄"
    5 -> "▅"
    6 -> "▆"
    7 -> "▇"
    _ -> "█"
  }
}

fn cell_color(
  fill: SparkFill,
  x: Int,
  width: Int,
  frame: Int,
  period: Int,
) -> style.Color {
  let p = int.max(1, period)
  let w = int.max(1, width)
  case fill {
    SparkSolid(c) -> c
    SparkGradient(stops) -> color.gradient(stops, x, w - 1)
    SparkAnimated(stops) -> {
      let offset = frame * w / p
      color.gradient(stops, { x + offset } % w, w - 1)
    }
    SparkRainbow -> color.hue_to_rgb(x * 360 / w)
    SparkAnimatedRainbow ->
      color.hue_to_rgb({ x * 360 / w + frame * 360 / p } % 360)
  }
}
