/// Vertical bar chart widget.
/// Each data point renders as a column of filled block cells.
/// Supports gradient/rainbow/animated fills per bar.
import etui/buffer
import etui/color
import etui/geometry
import etui/style
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

pub type ChartFill {
  /// One color per bar; wraps if more bars than colors.
  ChartSolid(colors: List(style.Color))
  /// Gradient applied left-to-right across all bars.
  ChartGradient(stops: List(style.Color))
  /// Rainbow, one hue per bar.
  ChartRainbow
  /// Rainbow that rotates hue over time.
  ChartAnimatedRainbow
  /// Gradient from bottom (cold) to top (warm), per cell.
  ChartVerticalGradient(stops: List(style.Color))
}

pub type Chart {
  Chart(
    data: List(Int),
    /// 0 = auto-compute from data.
    max_val: Int,
    fill: ChartFill,
    /// Width in chars of each bar.
    bar_width: Int,
    /// Width in chars of gap between bars.
    gap: Int,
    /// Character used for filled cells.
    bar_char: String,
    bg: style.Color,
    /// Animation period in frames.
    period: Int,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

pub fn chart_new(data: List(Int)) -> Chart {
  Chart(
    data: data,
    max_val: 0,
    fill: ChartRainbow,
    bar_width: 2,
    gap: 1,
    bar_char: "█",
    bg: style.Default,
    period: 60,
  )
}

pub fn with_fill(c: Chart, fill: ChartFill) -> Chart {
  Chart(..c, fill: fill)
}

pub fn with_max(c: Chart, max: Int) -> Chart {
  Chart(..c, max_val: int.max(1, max))
}

pub fn with_bar_width(c: Chart, w: Int) -> Chart {
  Chart(..c, bar_width: int.max(1, w))
}

pub fn with_gap(c: Chart, g: Int) -> Chart {
  Chart(..c, gap: int.max(0, g))
}

pub fn with_period(c: Chart, period: Int) -> Chart {
  Chart(..c, period: int.max(1, period))
}

pub fn with_bg(c: Chart, bg: style.Color) -> Chart {
  Chart(..c, bg: bg)
}

pub fn with_style(c: Chart, s: style.Style) -> Chart {
  Chart(..c, bg: s.bg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render chart into `area`. `frame` drives animated fills.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  c: Chart,
  frame: Int,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let max = case c.max_val {
        0 -> list.fold(c.data, 1, int.max)
        m -> m
      }
      let n_bars = list.length(c.data)
      render_bars(buf, area, c, c.data, 0, n_bars, max, frame)
    }
  }
}

fn render_bars(
  buf: buffer.Buffer,
  area: geometry.Rect,
  c: Chart,
  data: List(Int),
  bar_idx: Int,
  n_bars: Int,
  max: Int,
  frame: Int,
) -> buffer.Buffer {
  case data {
    [] -> buf
    [val, ..rest] -> {
      let col_start = bar_idx * { c.bar_width + c.gap }
      case col_start >= area.size.width {
        True -> buf
        False -> {
          let h = area.size.height
          // how many rows (from bottom) to fill for this bar
          let filled_rows = val * h / int.max(1, max)
          let buf2 =
            render_bar_col(
              buf,
              area,
              c,
              bar_idx,
              n_bars,
              col_start,
              h,
              filled_rows,
              frame,
            )
          render_bars(buf2, area, c, rest, bar_idx + 1, n_bars, max, frame)
        }
      }
    }
  }
}

fn render_bar_col(
  buf: buffer.Buffer,
  area: geometry.Rect,
  c: Chart,
  bar_idx: Int,
  n_bars: Int,
  col_start: Int,
  height: Int,
  filled_rows: Int,
  frame: Int,
) -> buffer.Buffer {
  render_bar_cols_inner(
    buf,
    area,
    c,
    bar_idx,
    n_bars,
    col_start,
    height,
    filled_rows,
    frame,
    0,
  )
}

fn render_bar_cols_inner(
  buf: buffer.Buffer,
  area: geometry.Rect,
  c: Chart,
  bar_idx: Int,
  n_bars: Int,
  col_start: Int,
  height: Int,
  filled_rows: Int,
  frame: Int,
  dc: Int,
) -> buffer.Buffer {
  case dc >= c.bar_width {
    True -> buf
    False -> {
      let x = col_start + dc
      case x >= area.size.width {
        True -> buf
        False -> {
          let buf2 =
            render_bar_rows(
              buf,
              area,
              c,
              bar_idx,
              n_bars,
              x,
              height,
              filled_rows,
              frame,
              0,
            )
          render_bar_cols_inner(
            buf2,
            area,
            c,
            bar_idx,
            n_bars,
            col_start,
            height,
            filled_rows,
            frame,
            dc + 1,
          )
        }
      }
    }
  }
}

fn render_bar_rows(
  buf: buffer.Buffer,
  area: geometry.Rect,
  c: Chart,
  bar_idx: Int,
  n_bars: Int,
  x: Int,
  height: Int,
  filled_rows: Int,
  frame: Int,
  dy: Int,
) -> buffer.Buffer {
  case dy >= height {
    True -> buf
    False -> {
      // dy=0 is top of chart; dy=height-1 is bottom
      let rows_from_bottom = height - 1 - dy
      let is_filled = rows_from_bottom < filled_rows
      let pos =
        geometry.Position(x: area.position.x + x, y: area.position.y + dy)
      let buf2 = case is_filled {
        True -> {
          let fg =
            bar_color(c.fill, bar_idx, n_bars, dy, height, frame, c.period)
          buffer.set_string(buf, pos, c.bar_char, fg, c.bg, style.none())
        }
        False -> buf
      }
      render_bar_rows(
        buf2,
        area,
        c,
        bar_idx,
        n_bars,
        x,
        height,
        filled_rows,
        frame,
        dy + 1,
      )
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Color dispatch

fn bar_color(
  fill: ChartFill,
  bar_idx: Int,
  n_bars: Int,
  dy: Int,
  height: Int,
  frame: Int,
  period: Int,
) -> style.Color {
  let p = int.max(1, period)
  let n = int.max(1, n_bars)
  let h = int.max(1, height)
  case fill {
    ChartSolid(colors) -> get_nth_color(colors, bar_idx)
    ChartGradient(stops) -> color.gradient(stops, bar_idx, n - 1)
    ChartRainbow -> color.hue_to_rgb(bar_idx * 360 / n)
    ChartAnimatedRainbow ->
      color.hue_to_rgb({ bar_idx * 360 / n + frame * 360 / p } % 360)
    ChartVerticalGradient(stops) ->
      color.gradient(stops, height - 1 - dy, h - 1)
  }
}

fn get_nth_color(colors: List(style.Color), n: Int) -> style.Color {
  let len = list.length(colors)
  case len {
    0 -> style.Default
    _ -> get_color_at(colors, n % len)
  }
}

fn get_color_at(colors: List(style.Color), n: Int) -> style.Color {
  case colors, n {
    [], _ -> style.Default
    [c, ..], 0 -> c
    [_, ..rest], _ -> get_color_at(rest, n - 1)
  }
}
