import etui/buffer
import etui/color
import etui/geometry
import etui/style
import gleam/int

// ─────────────────────────────────────────────────────────────────
// Types

pub type GradientFill {
  /// Static left-to-right gradient across color stops.
  LinearGradient(stops: List(style.Color))
  /// Gradient that scrolls left over time.
  AnimatedLinear(stops: List(style.Color))
  /// Static full-spectrum rainbow.
  Rainbow
  /// Rainbow that rotates hue over time.
  AnimatedRainbow
  /// Single color that oscillates between half and full brightness.
  Pulse(base: style.Color)
}

pub type GradientBar {
  GradientBar(
    fill: GradientFill,
    filled_char: String,
    empty_char: String,
    /// 0–100: how much of the bar is filled.
    percent: Int,
    modifier: style.Modifier,
    bg: style.Color,
    /// Animation period in frames.
    period: Int,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// Static linear gradient bar (full width).
pub fn gradient_bar_new(stops: List(style.Color)) -> GradientBar {
  GradientBar(
    fill: LinearGradient(stops),
    filled_char: "█",
    empty_char: "░",
    percent: 100,
    modifier: style.none(),
    bg: style.Default,
    period: 60,
  )
}

/// Animated (scrolling) gradient bar (full width).
pub fn animated_gradient_bar_new(stops: List(style.Color)) -> GradientBar {
  GradientBar(
    fill: AnimatedLinear(stops),
    filled_char: "█",
    empty_char: "░",
    percent: 100,
    modifier: style.none(),
    bg: style.Default,
    period: 60,
  )
}

/// Static rainbow bar (full width).
pub fn rainbow_bar() -> GradientBar {
  GradientBar(
    fill: Rainbow,
    filled_char: "█",
    empty_char: " ",
    percent: 100,
    modifier: style.none(),
    bg: style.Default,
    period: 60,
  )
}

/// Animated (rotating) rainbow bar (full width).
pub fn animated_rainbow_bar() -> GradientBar {
  GradientBar(
    fill: AnimatedRainbow,
    filled_char: "█",
    empty_char: " ",
    percent: 100,
    modifier: style.none(),
    bg: style.Default,
    period: 60,
  )
}

/// Pulsing single-color bar (full width).
pub fn pulse_bar(base: style.Color) -> GradientBar {
  GradientBar(
    fill: Pulse(base),
    filled_char: "█",
    empty_char: " ",
    percent: 100,
    modifier: style.none(),
    bg: style.Default,
    period: 30,
  )
}

/// Gradient progress bar: partial fill, static gradient.
pub fn gradient_progress_new(
  stops: List(style.Color),
  percent: Int,
) -> GradientBar {
  GradientBar(
    fill: LinearGradient(stops),
    filled_char: "█",
    empty_char: "░",
    percent: int.clamp(percent, 0, 100),
    modifier: style.none(),
    bg: style.Default,
    period: 60,
  )
}

// ─────────────────────────────────────────────────────────────────
// Config helpers

pub fn with_percent(g: GradientBar, pct: Int) -> GradientBar {
  GradientBar(..g, percent: int.clamp(pct, 0, 100))
}

pub fn with_chars(
  g: GradientBar,
  filled: String,
  empty: String,
) -> GradientBar {
  GradientBar(..g, filled_char: filled, empty_char: empty)
}

pub fn with_period(g: GradientBar, period: Int) -> GradientBar {
  GradientBar(..g, period: int.max(1, period))
}

pub fn with_modifier(g: GradientBar, m: style.Modifier) -> GradientBar {
  GradientBar(..g, modifier: m)
}

pub fn with_bg(g: GradientBar, bg: style.Color) -> GradientBar {
  GradientBar(..g, bg: bg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the gradient bar into `buf` at `area`. `frame` drives animation.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  g: GradientBar,
  frame: Int,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let width = area.size.width
      let fill_width = width * int.clamp(g.percent, 0, 100) / 100
      render_rows(buf, area, g, frame, width, fill_width, 0)
    }
  }
}

fn render_rows(
  buf: buffer.Buffer,
  area: geometry.Rect,
  g: GradientBar,
  frame: Int,
  width: Int,
  fill_width: Int,
  y: Int,
) -> buffer.Buffer {
  case y >= area.size.height {
    True -> buf
    False -> {
      let buf2 = render_row_cells(buf, area, g, frame, width, fill_width, 0, y)
      render_rows(buf2, area, g, frame, width, fill_width, y + 1)
    }
  }
}

fn render_row_cells(
  buf: buffer.Buffer,
  area: geometry.Rect,
  g: GradientBar,
  frame: Int,
  width: Int,
  fill_width: Int,
  x: Int,
  y: Int,
) -> buffer.Buffer {
  case x >= width {
    True -> buf
    False -> {
      let pos =
        geometry.Position(x: area.position.x + x, y: area.position.y + y)
      let #(sym, fg) = case x < fill_width {
        True -> {
          let c = cell_color(g.fill, x, fill_width, frame, g.period)
          #(g.filled_char, c)
        }
        False -> #(g.empty_char, style.Default)
      }
      let buf2 = buffer.set_string(buf, pos, sym, fg, g.bg, g.modifier)
      render_row_cells(buf2, area, g, frame, width, fill_width, x + 1, y)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Color dispatch

fn cell_color(
  fill: GradientFill,
  x: Int,
  width: Int,
  frame: Int,
  period: Int,
) -> style.Color {
  let p = int.max(1, period)
  let w = int.max(1, width)
  case fill {
    LinearGradient(stops) -> color.gradient(stops, x, w - 1)
    AnimatedLinear(stops) -> {
      let offset = frame * w / p
      color.gradient(stops, { x + offset } % w, w - 1)
    }
    Rainbow -> color.hue_to_rgb(x * 360 / w)
    AnimatedRainbow -> color.hue_to_rgb({ x * 360 / w + frame * 360 / p } % 360)
    Pulse(base) -> color.pulse(base, frame + x * p / w, p)
  }
}
