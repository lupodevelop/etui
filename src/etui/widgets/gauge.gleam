/// Gauge widget: horizontal progress bar with optional centered label.
///
/// Renders a filled portion (default `█`) and an empty portion (default `░`)
/// proportional to `percent` (0–100). An optional label is overlaid centered.
///
/// Example:
/// ```gleam
/// gauge_new(60)
/// |> with_label("60%")
/// |> gauge.render(buf, area)
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int

// ─────────────────────────────────────────────────────────────────
// Types

/// Horizontal progress bar. `percent` is clamped to 0–100.
pub type Gauge {
  Gauge(
    percent: Int,
    label: String,
    filled_char: String,
    empty_char: String,
    fg: style.Color,
    bg: style.Color,
    filled_modifier: style.Modifier,
    empty_modifier: style.Modifier,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New gauge at the given percent (clamped to 0–100). Default chars: `█`/`░`.
pub fn gauge_new(percent: Int) -> Gauge {
  Gauge(
    percent: int.clamp(percent, 0, 100),
    label: "",
    filled_char: "█",
    empty_char: "░",
    fg: style.Default,
    bg: style.Default,
    filled_modifier: style.none(),
    empty_modifier: style.none(),
  )
}

/// Set a label overlaid centered on the bar.
pub fn with_label(g: Gauge, label: String) -> Gauge {
  Gauge(..g, label: label)
}

/// Set filled and empty characters (single-cell graphemes only).
pub fn with_chars(g: Gauge, filled: String, empty: String) -> Gauge {
  Gauge(..g, filled_char: filled, empty_char: empty)
}

/// Set fg/bg colors for both filled and empty sections.
pub fn with_colors(g: Gauge, fg: style.Color, bg: style.Color) -> Gauge {
  Gauge(..g, fg: fg, bg: bg)
}

/// Apply a modifier (bold, etc.) to the filled section only.
pub fn with_filled_modifier(g: Gauge, modifier: style.Modifier) -> Gauge {
  Gauge(..g, filled_modifier: modifier)
}

/// Apply a style (fg/bg) via a `Style` value.
pub fn with_style(g: Gauge, s: style.Style) -> Gauge {
  Gauge(..g, fg: s.fg, bg: s.bg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the gauge bar into the first row of `area`.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  g: Gauge,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> render_bar(buf, area, g)
  }
}

fn render_bar(
  buf: buffer.Buffer,
  area: geometry.Rect,
  g: Gauge,
) -> buffer.Buffer {
  let width = area.size.width
  let filled = int.clamp(width * g.percent / 100, 0, width)
  let empty = width - filled

  let buf1 =
    fill_cells(
      buf,
      area.position,
      filled,
      g.filled_char,
      g.fg,
      g.bg,
      g.filled_modifier,
    )
  let buf2 =
    fill_cells(
      buf1,
      geometry.Position(x: area.position.x + filled, y: area.position.y),
      empty,
      g.empty_char,
      g.fg,
      g.bg,
      g.empty_modifier,
    )

  case g.label {
    "" -> buf2
    label -> {
      let label_width = text.cell_width(label)
      let label_x = area.position.x + int.max(0, { width - label_width } / 2)
      buffer.set_string(
        buf2,
        geometry.Position(x: label_x, y: area.position.y),
        text.truncate(label, width, ""),
        g.fg,
        g.bg,
        style.none(),
      )
    }
  }
}

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
