/// LineGauge: a thin single-row progress indicator using Unicode line characters.
///
/// Unlike `Gauge` which fills cells with block chars, LineGauge draws a
/// horizontal line with a ratio indicator, minimal and text-friendly.
///
/// ```gleam
/// line_gauge_new(75)
/// |> with_label("75%")
/// |> with_line_set(line_gauge.ThinLine)
/// |> line_gauge.render(buf, area)
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

/// Character set for the gauge line.
pub type LineSet {
  /// Thin Unicode line (─ ╴ ╶)
  ThinLine
  /// Double Unicode line (═ ╸ ╺)
  DoubleLine
  /// Thick line (━ ╸ ╺)
  ThickLine
  /// Braille dots (⣿ ⣀)
  BrailleLine
  /// ASCII fallback (= -)
  AsciiLine
}

/// Line gauge configuration.
pub type LineGauge {
  LineGauge(
    /// Progress ratio 0–100 (clamped).
    percent: Int,
    /// Optional text overlaid in the center.
    label: String,
    /// Line character set.
    line_set: LineSet,
    /// Foreground color (filled portion and label).
    fg: style.Color,
    /// Background color (unfilled portion).
    bg: style.Color,
    /// Modifier applied to the filled portion.
    filled_modifier: style.Modifier,
    /// Modifier applied to the unfilled portion.
    unfilled_modifier: style.Modifier,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New line gauge at the given percent (clamped to 0–100).
pub fn line_gauge_new(percent: Int) -> LineGauge {
  LineGauge(
    percent: int.clamp(percent, 0, 100),
    label: "",
    line_set: ThinLine,
    fg: style.Default,
    bg: style.Default,
    filled_modifier: style.none(),
    unfilled_modifier: style.dim(),
  )
}

/// Set a label shown in the center of the gauge.
pub fn with_label(g: LineGauge, label: String) -> LineGauge {
  LineGauge(..g, label: label)
}

/// Set the line character set.
pub fn with_line_set(g: LineGauge, ls: LineSet) -> LineGauge {
  LineGauge(..g, line_set: ls)
}

/// Set foreground and background colors.
pub fn with_colors(
  g: LineGauge,
  fg: style.Color,
  bg: style.Color,
) -> LineGauge {
  LineGauge(..g, fg: fg, bg: bg)
}

/// Set fg/bg from a Style value.
pub fn with_style(g: LineGauge, s: style.Style) -> LineGauge {
  LineGauge(..g, fg: s.fg, bg: s.bg)
}

/// Apply a modifier to the filled portion.
pub fn with_filled_modifier(g: LineGauge, m: style.Modifier) -> LineGauge {
  LineGauge(..g, filled_modifier: m)
}

// ─────────────────────────────────────────────────────────────────
// Line character sets

type LineChars {
  LineChars(filled: String, unfilled: String)
}

fn line_chars(ls: LineSet) -> LineChars {
  case ls {
    ThinLine -> LineChars(filled: "─", unfilled: "─")
    DoubleLine -> LineChars(filled: "═", unfilled: "═")
    ThickLine -> LineChars(filled: "━", unfilled: "─")
    BrailleLine -> LineChars(filled: "⣿", unfilled: "⣀")
    AsciiLine -> LineChars(filled: "=", unfilled: "-")
  }
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the line gauge into the first row of `area`.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  g: LineGauge,
) -> buffer.Buffer {
  case area.size.width <= 0 {
    True -> buf
    False -> {
      let width = area.size.width
      let filled_w = width * g.percent / 100
      let unfilled_w = width - filled_w
      let chars = line_chars(g.line_set)
      let filled_str = repeat_char(chars.filled, filled_w)
      let unfilled_str = repeat_char(chars.unfilled, unfilled_w)

      // Optionally overlay label in center
      let raw_line = filled_str <> unfilled_str
      let line = case g.label {
        "" -> raw_line
        _ -> overlay_label(raw_line, g.label, width)
      }

      let pos = area.position
      let y = pos.y

      // Write filled portion
      let buf =
        buffer.set_string(
          buf,
          geometry.Position(x: pos.x, y: y),
          text.truncate(line, filled_w, ""),
          g.fg,
          g.bg,
          g.filled_modifier,
        )

      // Write unfilled portion
      buffer.set_string(
        buf,
        geometry.Position(x: pos.x + filled_w, y: y),
        text.truncate(drop_cells(line, filled_w), unfilled_w, ""),
        g.fg,
        g.bg,
        g.unfilled_modifier,
      )
    }
  }
}

fn repeat_char(ch: String, n: Int) -> String {
  repeat_char_loop(ch, n, "")
}

fn repeat_char_loop(ch: String, n: Int, acc: String) -> String {
  case n <= 0 {
    True -> acc
    False -> repeat_char_loop(ch, n - 1, acc <> ch)
  }
}

// Overlay label centered on base string (same total cell width).
fn overlay_label(base: String, label: String, width: Int) -> String {
  let lw = text.cell_width(label)
  case lw >= width {
    True -> text.truncate(label, width, "")
    False -> {
      let left_pad = { width - lw } / 2
      let right_pad = width - lw - left_pad
      let left_str = text.truncate(base, left_pad, "")
      let right_str =
        text.truncate(drop_cells(base, left_pad + lw), right_pad, "")
      left_str <> label <> right_str
    }
  }
}

// Drop `n` cell-widths from the start of a string (grapheme-accurate).
fn drop_cells(s: String, n: Int) -> String {
  case n <= 0 {
    True -> s
    False -> {
      let prefix = text.truncate(s, n, "")
      string.drop_start(s, string.length(prefix))
    }
  }
}
