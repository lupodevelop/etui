/// Horizontal bar chart widget.
/// Each item renders as one labelled row with a left-to-right filled bar.
/// Supports gradient/rainbow/animated fill.
import etui/buffer
import etui/color
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

pub type HBarFill {
  /// Cycle through a list of solid colors, one per bar.
  HBarSolid(colors: List(style.Color))
  /// Static left-to-right gradient applied to each bar's filled cells.
  HBarGradient(stops: List(style.Color))
  /// Each bar gets a different hue; static rainbow.
  HBarRainbow
  /// Rainbow that rotates hue over time.
  HBarAnimatedRainbow
}

pub type HBarItem {
  HBarItem(label: String, value: Int)
}

pub type HBar {
  HBar(
    items: List(HBarItem),
    /// 0 = auto-compute max from data.
    max_val: Int,
    fill: HBarFill,
    /// Width reserved for labels. 0 = auto (longest label).
    label_width: Int,
    /// Whether to append the numeric value after the bar.
    show_value: Bool,
    bar_char: String,
    empty_char: String,
    bg: style.Color,
    period: Int,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

pub fn hbar_new(items: List(HBarItem)) -> HBar {
  HBar(
    items: items,
    max_val: 0,
    fill: HBarRainbow,
    label_width: 0,
    show_value: True,
    bar_char: "█",
    empty_char: "░",
    bg: style.Default,
    period: 60,
  )
}

pub fn item(label: String, value: Int) -> HBarItem {
  HBarItem(label: label, value: value)
}

pub fn with_fill(h: HBar, fill: HBarFill) -> HBar {
  HBar(..h, fill: fill)
}

pub fn with_max(h: HBar, max: Int) -> HBar {
  HBar(..h, max_val: int.max(1, max))
}

pub fn with_label_width(h: HBar, w: Int) -> HBar {
  HBar(..h, label_width: int.max(0, w))
}

pub fn with_show_value(h: HBar, show: Bool) -> HBar {
  HBar(..h, show_value: show)
}

pub fn with_chars(h: HBar, bar: String, empty: String) -> HBar {
  HBar(..h, bar_char: bar, empty_char: empty)
}

pub fn with_period(h: HBar, period: Int) -> HBar {
  HBar(..h, period: int.max(1, period))
}

pub fn with_bg(h: HBar, bg: style.Color) -> HBar {
  HBar(..h, bg: bg)
}

pub fn with_style(h: HBar, s: style.Style) -> HBar {
  HBar(..h, bg: s.bg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  h: HBar,
  frame: Int,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let max = case h.max_val {
        0 -> list.fold(h.items, 1, fn(acc, it) { int.max(acc, it.value) })
        m -> m
      }
      let lw = case h.label_width {
        0 ->
          list.fold(h.items, 0, fn(acc, it) {
            int.max(acc, text.cell_width(it.label))
          })
        w -> w
      }
      let val_w = case h.show_value {
        False -> 0
        True -> num_digits(max) + 2
      }
      let n = list.length(h.items)
      render_rows(buf, area, h, h.items, 0, n, max, lw, val_w, frame)
    }
  }
}

fn render_rows(
  buf: buffer.Buffer,
  area: geometry.Rect,
  h: HBar,
  items: List(HBarItem),
  idx: Int,
  n: Int,
  max: Int,
  lw: Int,
  val_w: Int,
  frame: Int,
) -> buffer.Buffer {
  case items {
    [] -> buf
    [it, ..rest] -> {
      case idx >= area.size.height {
        True -> buf
        False -> {
          let y = area.position.y + idx
          let buf2 =
            render_row(buf, area, h, it, idx, n, max, lw, val_w, y, frame)
          render_rows(buf2, area, h, rest, idx + 1, n, max, lw, val_w, frame)
        }
      }
    }
  }
}

fn render_row(
  buf: buffer.Buffer,
  area: geometry.Rect,
  h: HBar,
  it: HBarItem,
  idx: Int,
  n: Int,
  max: Int,
  lw: Int,
  val_w: Int,
  y: Int,
  frame: Int,
) -> buffer.Buffer {
  // Label (left-aligned, fixed width)
  let label = text.pad_right(text.truncate(it.label, lw, ""), lw)
  let buf =
    buffer.set_string(
      buf,
      geometry.Position(x: area.position.x, y: y),
      label,
      style.Default,
      style.Default,
      style.none(),
    )
  // Bar area
  let bar_x = area.position.x + lw + 1
  let bar_w = int.max(0, area.size.width - lw - 1 - val_w)
  let filled = int.clamp(it.value * bar_w / int.max(1, max), 0, bar_w)
  let empty = bar_w - filled
  // Filled cells with color
  let buf = render_filled(buf, h, idx, n, bar_x, y, filled, bar_w, frame)
  // Empty cells
  let buf = render_empty(buf, h, bar_x + filled, y, empty)
  // Value label
  case h.show_value && val_w > 0 {
    False -> buf
    True ->
      buffer.set_string(
        buf,
        geometry.Position(x: bar_x + bar_w + 1, y: y),
        int.to_string(it.value),
        style.Default,
        style.Default,
        style.none(),
      )
  }
}

fn render_filled(
  buf: buffer.Buffer,
  h: HBar,
  bar_idx: Int,
  n: Int,
  base_x: Int,
  y: Int,
  count: Int,
  bar_w: Int,
  frame: Int,
) -> buffer.Buffer {
  render_filled_loop(buf, h, bar_idx, n, base_x, y, count, bar_w, frame, 0)
}

fn render_filled_loop(
  buf: buffer.Buffer,
  h: HBar,
  bar_idx: Int,
  n: Int,
  base_x: Int,
  y: Int,
  count: Int,
  bar_w: Int,
  frame: Int,
  i: Int,
) -> buffer.Buffer {
  case i >= count {
    True -> buf
    False -> {
      let fg = cell_color(h.fill, bar_idx, n, i, bar_w, frame, h.period)
      let buf2 =
        buffer.set_string(
          buf,
          geometry.Position(x: base_x + i, y: y),
          h.bar_char,
          fg,
          h.bg,
          style.none(),
        )
      render_filled_loop(
        buf2,
        h,
        bar_idx,
        n,
        base_x,
        y,
        count,
        bar_w,
        frame,
        i + 1,
      )
    }
  }
}

fn render_empty(
  buf: buffer.Buffer,
  h: HBar,
  base_x: Int,
  y: Int,
  count: Int,
) -> buffer.Buffer {
  render_empty_loop(buf, h, base_x, y, count, 0)
}

fn render_empty_loop(
  buf: buffer.Buffer,
  h: HBar,
  base_x: Int,
  y: Int,
  count: Int,
  i: Int,
) -> buffer.Buffer {
  case i >= count {
    True -> buf
    False -> {
      let buf2 =
        buffer.set_string(
          buf,
          geometry.Position(x: base_x + i, y: y),
          h.empty_char,
          style.Default,
          h.bg,
          style.none(),
        )
      render_empty_loop(buf2, h, base_x, y, count, i + 1)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Color dispatch

fn cell_color(
  fill: HBarFill,
  bar_idx: Int,
  n: Int,
  x: Int,
  bar_w: Int,
  frame: Int,
  period: Int,
) -> style.Color {
  let p = int.max(1, period)
  let nb = int.max(1, n)
  let w = int.max(1, bar_w)
  case fill {
    HBarSolid(colors) -> nth_color(colors, bar_idx)
    HBarGradient(stops) -> color.gradient(stops, x, w - 1)
    HBarRainbow -> color.hue_to_rgb(bar_idx * 360 / nb)
    HBarAnimatedRainbow ->
      color.hue_to_rgb({ bar_idx * 360 / nb + frame * 360 / p } % 360)
  }
}

fn nth_color(colors: List(style.Color), n: Int) -> style.Color {
  let len = list.length(colors)
  case len {
    0 -> style.Default
    _ -> color_at(colors, n % len)
  }
}

fn color_at(colors: List(style.Color), n: Int) -> style.Color {
  case colors, n {
    [], _ -> style.Default
    [c, ..], 0 -> c
    [_, ..rest], _ -> color_at(rest, n - 1)
  }
}

fn num_digits(n: Int) -> Int {
  case n < 10 {
    True -> 1
    False -> 1 + num_digits(n / 10)
  }
}
