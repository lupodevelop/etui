/// Animated progress bar widget.
/// Determinate: fill from 0..100%. Indeterminate: bouncing segment.
import etui/anim
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int

// ─────────────────────────────────────────────────────────────────
// Types

pub type ProgressMode {
  Determinate(percent: Int)
  Indeterminate
}

pub type ProgressBar {
  ProgressBar(
    mode: ProgressMode,
    label: String,
    filled_char: String,
    empty_char: String,
    /// Indeterminate segment size as a percentage of bar width (1–100).
    segment_width: Int,
    fg: style.Color,
    bg: style.Color,
    filled_modifier: style.Modifier,
    empty_modifier: style.Modifier,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

pub fn progress_new(percent: Int) -> ProgressBar {
  ProgressBar(
    mode: Determinate(int.clamp(percent, 0, 100)),
    label: "",
    filled_char: "█",
    empty_char: "░",
    segment_width: 25,
    fg: style.Default,
    bg: style.Default,
    filled_modifier: style.none(),
    empty_modifier: style.none(),
  )
}

pub fn progress_indeterminate() -> ProgressBar {
  ProgressBar(
    mode: Indeterminate,
    label: "",
    filled_char: "█",
    empty_char: "░",
    segment_width: 25,
    fg: style.Default,
    bg: style.Default,
    filled_modifier: style.none(),
    empty_modifier: style.none(),
  )
}

pub fn with_label(p: ProgressBar, label: String) -> ProgressBar {
  ProgressBar(..p, label: label)
}

pub fn with_chars(
  p: ProgressBar,
  filled: String,
  empty: String,
) -> ProgressBar {
  ProgressBar(..p, filled_char: filled, empty_char: empty)
}

/// Indeterminate segment size as a percentage of bar width (1–100).
pub fn with_segment_width(p: ProgressBar, pct: Int) -> ProgressBar {
  ProgressBar(..p, segment_width: int.clamp(pct, 1, 100))
}

pub fn with_colors(
  p: ProgressBar,
  fg: style.Color,
  bg: style.Color,
) -> ProgressBar {
  ProgressBar(..p, fg: fg, bg: bg)
}

pub fn with_style(p: ProgressBar, s: style.Style) -> ProgressBar {
  ProgressBar(..p, fg: s.fg, bg: s.bg)
}

pub fn with_filled_modifier(p: ProgressBar, m: style.Modifier) -> ProgressBar {
  ProgressBar(..p, filled_modifier: m)
}

pub fn with_empty_modifier(p: ProgressBar, m: style.Modifier) -> ProgressBar {
  ProgressBar(..p, empty_modifier: m)
}

// ─────────────────────────────────────────────────────────────────
// Rendering
//
// `frame` is required even for Determinate bars so the API is uniform.
// Determinate bars ignore the frame; Indeterminate bars use it to
// animate the bouncing segment.

pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  p: ProgressBar,
  frame: Int,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False ->
      case p.mode {
        Determinate(pct) -> render_determinate(buf, area, p, pct)
        Indeterminate -> render_indeterminate(buf, area, p, frame)
      }
  }
}

fn render_determinate(
  buf: buffer.Buffer,
  area: geometry.Rect,
  p: ProgressBar,
  pct: Int,
) -> buffer.Buffer {
  let width = area.size.width
  let filled = int.clamp(width * pct / 100, 0, width)
  let empty = width - filled
  let buf1 =
    fill_cells(
      buf,
      area.position,
      filled,
      p.filled_char,
      p.fg,
      p.bg,
      p.filled_modifier,
    )
  let buf2 =
    fill_cells(
      buf1,
      geometry.Position(x: area.position.x + filled, y: area.position.y),
      empty,
      p.empty_char,
      p.fg,
      p.bg,
      p.empty_modifier,
    )
  case p.label {
    "" -> buf2
    label -> {
      let lw = text.cell_width(label)
      let lx = area.position.x + int.max(0, { width - lw } / 2)
      buffer.set_string(
        buf2,
        geometry.Position(x: lx, y: area.position.y),
        text.truncate(label, width, ""),
        p.fg,
        p.bg,
        style.none(),
      )
    }
  }
}

fn render_indeterminate(
  buf: buffer.Buffer,
  area: geometry.Rect,
  p: ProgressBar,
  frame: Int,
) -> buffer.Buffer {
  let width = area.size.width
  let seg = int.max(1, width * p.segment_width / 100)
  let max_start = int.max(0, width - seg)
  // period = full bounce: 0 → max_start → 0
  let period = int.max(1, { max_start + seg } * 2)
  let seg_start = anim.oscillate(0, max_start, frame, period)
  // Fill bar with empty chars, then overlay segment
  let buf1 =
    fill_cells(
      buf,
      area.position,
      width,
      p.empty_char,
      p.fg,
      p.bg,
      p.empty_modifier,
    )
  fill_cells(
    buf1,
    geometry.Position(x: area.position.x + seg_start, y: area.position.y),
    seg,
    p.filled_char,
    p.fg,
    p.bg,
    p.filled_modifier,
  )
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

fn fill_cells(
  buf: buffer.Buffer,
  pos: geometry.Position,
  count: Int,
  char: String,
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
) -> buffer.Buffer {
  do_fill(buf, pos, count, 0, char, fg, bg, modifier)
}

fn do_fill(
  buf: buffer.Buffer,
  start: geometry.Position,
  count: Int,
  i: Int,
  char: String,
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
) -> buffer.Buffer {
  case i >= count {
    True -> buf
    False -> {
      let pos = geometry.Position(x: start.x + i, y: start.y)
      let buf_new =
        buffer.set_cell(
          buf,
          pos,
          buffer.Cell(
            content: buffer.Content(symbol: char, width: 1),
            fg: fg,
            bg: bg,
            modifier: modifier,
            link: "",
          ),
        )
      do_fill(buf_new, start, count, i + 1, char, fg, bg, modifier)
    }
  }
}
