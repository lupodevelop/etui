/// Horizontal rule with an optional inline title.
/// Renders one row, full width: `── Title ────────────`.
/// Title alignment can be left, center or right.
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

/// Where the title sits along the rule.
pub type FieldsetAlign {
  AlignLeft
  AlignCenter
  AlignRight
}

pub type Fieldset {
  Fieldset(
    title: String,
    align: FieldsetAlign,
    line_char: String,
    /// Padding rule chars on the title side. Ignored when align is `AlignCenter`.
    pad: Int,
    fg: style.Color,
    bg: style.Color,
    title_fg: style.Color,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// A left-aligned fieldset with the given title and thin rules.
pub fn fieldset_new(title: String) -> Fieldset {
  Fieldset(
    title: title,
    align: AlignLeft,
    line_char: "─",
    pad: 2,
    fg: style.Default,
    bg: style.Default,
    title_fg: style.Default,
  )
}

/// Move the title along the rule. Centered titles ignore `pad`.
pub fn with_align(fs: Fieldset, a: FieldsetAlign) -> Fieldset {
  Fieldset(..fs, align: a)
}

/// Replace the rule character (e.g. `"═"` for a double rule).
pub fn with_line_char(fs: Fieldset, c: String) -> Fieldset {
  Fieldset(..fs, line_char: c)
}

/// Rule chars between the screen edge and the title. Clamped to ≥ 0.
pub fn with_pad(fs: Fieldset, p: Int) -> Fieldset {
  Fieldset(..fs, pad: int.max(0, p))
}

/// Colors of the rule; the background also applies to the title.
pub fn with_colors(fs: Fieldset, fg: style.Color, bg: style.Color) -> Fieldset {
  Fieldset(..fs, fg: fg, bg: bg)
}

/// Color of the title text (rendered bold).
pub fn with_title_color(fs: Fieldset, fg: style.Color) -> Fieldset {
  Fieldset(..fs, title_fg: fg)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Draw the rule into the first row of `area`. An empty title renders a plain
/// rule across the full width.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  fs: Fieldset,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      let w = area.size.width
      let title_w = text.cell_width(fs.title)
      case title_w {
        0 -> {
          let line = string.repeat(fs.line_char, w)
          buffer.set_string(
            buf,
            area.position,
            line,
            style.new(fs.fg, fs.bg, style.none()),
          )
        }
        _ -> {
          // 1-cell space each side of title.
          let label_w = title_w + 2
          let avail = int.max(0, w - label_w)
          let #(left_n, right_n) = case fs.align {
            AlignLeft -> #(fs.pad, int.max(0, avail - fs.pad))
            AlignRight -> #(int.max(0, avail - fs.pad), fs.pad)
            AlignCenter -> {
              let half = avail / 2
              #(half, avail - half)
            }
          }
          let left = string.repeat(fs.line_char, left_n)
          let right = string.repeat(fs.line_char, right_n)
          let buf2 =
            buffer.set_string(
              buf,
              area.position,
              left,
              style.new(fs.fg, fs.bg, style.none()),
            )
          let buf3 =
            buffer.set_string(
              buf2,
              geometry.Position(x: area.position.x + left_n, y: area.position.y),
              " " <> fs.title <> " ",
              style.new(fs.title_fg, fs.bg, style.bold()),
            )
          buffer.set_string(
            buf3,
            geometry.Position(
              x: area.position.x + left_n + label_w,
              y: area.position.y,
            ),
            right,
            style.new(fs.fg, fs.bg, style.none()),
          )
        }
      }
    }
  }
}
