/// Marquee: horizontally scrolling text ticker.
/// The text wraps around continuously. `speed` controls how many frames
/// elapse before advancing one character position.
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

pub type Marquee {
  Marquee(
    text: String,
    /// Frames per character advance. Higher = slower scroll. 0 or 1 = fastest.
    speed: Int,
    /// String appended between repetitions for visual separation.
    separator: String,
    fg: style.Color,
    bg: style.Color,
    modifier: style.Modifier,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

pub fn marquee_new(text: String) -> Marquee {
  Marquee(
    text: text,
    speed: 8,
    separator: "  ·  ",
    fg: style.Default,
    bg: style.Default,
    modifier: style.none(),
  )
}

pub fn with_speed(m: Marquee, speed: Int) -> Marquee {
  Marquee(..m, speed: int.max(1, speed))
}

pub fn with_separator(m: Marquee, sep: String) -> Marquee {
  Marquee(..m, separator: sep)
}

pub fn with_fg(m: Marquee, fg: style.Color) -> Marquee {
  Marquee(..m, fg: fg)
}

pub fn with_style(
  m: Marquee,
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
) -> Marquee {
  Marquee(..m, fg: fg, bg: bg, modifier: modifier)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the scrolling marquee. `frame` drives scroll position.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  m: Marquee,
  frame: Int,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let unit = m.text <> m.separator
      let unit_cells = text.cell_width(unit)
      case unit_cells <= 0 {
        True -> buf
        False -> {
          let speed = int.max(1, m.speed)
          let offset_cells = frame / speed % unit_cells
          // Double the unit so slicing across the wrap is trivial.
          let doubled = unit <> unit
          // Skip offset_cells cells using grapheme-accurate drop.
          let skip_graphemes =
            string.length(text.truncate(doubled, offset_cells, ""))
          let available = string.drop_start(doubled, skip_graphemes)
          let padded = text.pad_right(available, area.size.width)
          let line = text.truncate(padded, area.size.width, "")
          buffer.set_string(
            buf,
            geometry.Position(x: area.position.x, y: area.position.y),
            line,
            m.fg,
            m.bg,
            m.modifier,
          )
        }
      }
    }
  }
}
