/// Status bar widget: horizontal bar with left, center, and right sections.
///
/// Each section is a list of `span.Line` for mixed-style text.
/// Sections are laid out flush-left, centered, and flush-right within the bar.
///
/// Example:
/// ```gleam
/// let bar = statusbar.statusbar_new()
///   |> statusbar.with_left([span.line_new([span.span_new("INSERT", s)])])
///   |> statusbar.with_right([span.line_new([span.span_new("Ln 42", s)])])
/// statusbar.render(buf, area, bar)
/// ```
import etui/buffer
import etui/geometry
import etui/span
import etui/style
import etui/text
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

/// Status bar configuration with left, center, and right span sections.
pub type StatusBar {
  StatusBar(
    left: List(span.Line),
    center: List(span.Line),
    right: List(span.Line),
    fg: style.Color,
    bg: style.Color,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New status bar with empty sections and default colors.
pub fn statusbar_new() -> StatusBar {
  StatusBar(
    left: [],
    center: [],
    right: [],
    fg: style.Default,
    bg: style.Default,
  )
}

/// Set left section spans.
pub fn with_left(sb: StatusBar, lines: List(span.Line)) -> StatusBar {
  StatusBar(..sb, left: lines)
}

/// Set center section spans.
pub fn with_center(sb: StatusBar, lines: List(span.Line)) -> StatusBar {
  StatusBar(..sb, center: lines)
}

/// Set right section spans.
pub fn with_right(sb: StatusBar, lines: List(span.Line)) -> StatusBar {
  StatusBar(..sb, right: lines)
}

/// Set foreground and background colors for the bar background.
pub fn with_style(
  sb: StatusBar,
  fg: style.Color,
  bg: style.Color,
) -> StatusBar {
  StatusBar(..sb, fg: fg, bg: bg)
}

pub fn with_colors(
  sb: StatusBar,
  fg: style.Color,
  bg: style.Color,
) -> StatusBar {
  StatusBar(..sb, fg: fg, bg: bg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render status bar into the first row of `area`.
/// Only one row is used; remaining rows in `area` are untouched.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  sb: StatusBar,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let y = area.position.y
      let w = area.size.width

      // Fill background row
      let bg_row = text.pad_right("", w)
      let buf1 =
        buffer.set_string(
          buf,
          geometry.Position(x: area.position.x, y: y),
          bg_row,
          sb.fg,
          sb.bg,
          style.none(),
        )

      // Left section: render from x=0
      let buf2 = render_section(buf1, sb.left, area.position.x, y, w, sb)

      // Right section: measure width, render flush-right
      let right_width = section_width(sb.right)
      let right_x = area.position.x + w - right_width
      let buf3 = case right_x >= area.position.x {
        True -> render_section(buf2, sb.right, right_x, y, right_width, sb)
        False -> buf2
      }

      // Center section: measure width, render centered
      let center_width = section_width(sb.center)
      let center_x = area.position.x + { w - center_width } / 2
      render_section(buf3, sb.center, center_x, y, center_width, sb)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

fn render_section(
  buf: buffer.Buffer,
  lines: List(span.Line),
  x: Int,
  y: Int,
  max_w: Int,
  sb: StatusBar,
) -> buffer.Buffer {
  case lines {
    [] -> buf
    [line, ..] ->
      span.render_line(
        buf,
        geometry.Position(x: x, y: y),
        inherit_bar_style(line, sb),
        max_w,
      )
  }
}

fn section_width(lines: List(span.Line)) -> Int {
  case lines {
    [] -> 0
    [line, ..] -> span.line_width(line)
  }
}

fn inherit_bar_style(line: span.Line, sb: StatusBar) -> span.Line {
  span.line_aligned(
    list.map(line.spans, fn(sp: span.Span) {
      let fg = case sp.fg {
        style.Default -> sb.fg
        _ -> sp.fg
      }
      let bg = case sp.bg {
        style.Default -> sb.bg
        _ -> sp.bg
      }
      span.Span(..sp, fg: fg, bg: bg)
    }),
    line.alignment,
  )
}
