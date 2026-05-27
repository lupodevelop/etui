/// Line widget: horizontal and vertical dividers.
import etui/buffer
import etui/geometry
import etui/style

// ─────────────────────────────────────────────────────────────────
// Types

/// Drawing style for lines. Currently only `Solid` (─ / │).
pub type LineStyle {
  Solid
}

/// Horizontal or vertical divider with optional color.
pub type Line {
  Line(style: LineStyle, fg: style.Color)
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New solid line with default terminal color.
pub fn line_new() -> Line {
  Line(style: Solid, fg: style.Default)
}

/// Set the line color.
pub fn with_color(l: Line, color: style.Color) -> Line {
  Line(..l, fg: color)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render horizontal line.
pub fn render_horizontal(
  buf: buffer.Buffer,
  area: geometry.Rect,
  l: Line,
) -> buffer.Buffer {
  case area.size.width <= 0 {
    True -> buf
    False -> render_horizontal_line(buf, area, l, 0, "─")
  }
}

fn render_horizontal_line(
  buf: buffer.Buffer,
  area: geometry.Rect,
  l: Line,
  x: Int,
  char: String,
) -> buffer.Buffer {
  case x >= area.size.width {
    True -> buf
    False -> {
      let pos = geometry.Position(x: area.position.x + x, y: area.position.y)
      let buf_new =
        buffer.set_string(buf, pos, char, l.fg, style.Default, style.none())
      render_horizontal_line(buf_new, area, l, x + 1, char)
    }
  }
}

/// Render vertical line.
pub fn render_vertical(
  buf: buffer.Buffer,
  area: geometry.Rect,
  l: Line,
) -> buffer.Buffer {
  case area.size.height <= 0 {
    True -> buf
    False -> {
      let char = "│"
      render_vertical_line(buf, area, l, 0, char)
    }
  }
}

fn render_vertical_line(
  buf: buffer.Buffer,
  area: geometry.Rect,
  l: Line,
  y: Int,
  char: String,
) -> buffer.Buffer {
  case y >= area.size.height {
    True -> buf
    False -> {
      let pos = geometry.Position(x: area.position.x, y: area.position.y + y)
      let buf_new =
        buffer.set_string(buf, pos, char, l.fg, style.Default, style.none())
      render_vertical_line(buf_new, area, l, y + 1, char)
    }
  }
}
