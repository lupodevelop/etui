/// Styled text spans: inline mixed-style text for TUI widgets.
///
/// A `Span` is a styled text fragment. A `Line` is a list of spans
/// rendered left-to-right on a single terminal row. Use `render_line`
/// to draw a `Line` into a buffer at a given position.
///
/// Example:
/// ```gleam
/// let line = line_new([
///   span_styled("ERROR", style.bold_style() |> style.with_fg(style.Rgb(255,0,0))),
///   span_plain(" file not found"),
/// ])
/// span.render_line(buf, pos, line, 40)
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

/// A styled text fragment: string content + display style + optional hyperlink.
pub type Span {
  Span(
    content: String,
    fg: style.Color,
    bg: style.Color,
    modifier: style.Modifier,
    /// OSC 8 hyperlink URI. Empty string = no link.
    link: String,
  )
}

/// A single terminal row composed of styled spans.
pub type Line {
  Line(spans: List(Span), alignment: text.Alignment)
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// Span with default terminal colors and no modifier.
pub fn span_plain(content: String) -> Span {
  Span(
    content: content,
    fg: style.Default,
    bg: style.Default,
    modifier: style.none(),
    link: "",
  )
}

/// Span with explicit style applied.
pub fn span_styled(content: String, s: style.Style) -> Span {
  Span(content: content, fg: s.fg, bg: s.bg, modifier: s.modifier, link: "")
}

/// Span with an OSC 8 clickable hyperlink.
/// Terminals that support OSC 8 (iTerm2, Kitty, VTE, Windows Terminal) will
/// render the text as a clickable link. Others display it as plain text.
///
/// ```gleam
/// span.span_link("docs.gleam.run", "https://docs.gleam.run")
/// ```
pub fn span_link(content: String, uri: String) -> Span {
  Span(
    content: content,
    fg: style.Default,
    bg: style.Default,
    modifier: style.none(),
    link: uri,
  )
}

/// Add an OSC 8 hyperlink URI to an existing span.
pub fn with_link(sp: Span, uri: String) -> Span {
  Span(..sp, link: uri)
}

/// Set foreground color on a span.
pub fn span_fg(sp: Span, color: style.Color) -> Span {
  Span(..sp, fg: color)
}

/// Set background color on a span.
pub fn span_bg(sp: Span, color: style.Color) -> Span {
  Span(..sp, bg: color)
}

/// Add a modifier to a span.
pub fn span_modifier(sp: Span, modifier: style.Modifier) -> Span {
  Span(..sp, modifier: style.add(sp.modifier, modifier))
}

/// Total cell width of a span.
pub fn span_width(sp: Span) -> Int {
  text.cell_width(sp.content)
}

/// Line from a list of spans, left-aligned.
pub fn line_new(spans: List(Span)) -> Line {
  Line(spans: spans, alignment: text.Left)
}

/// Line with a single unstyled string, left-aligned.
pub fn line_plain(content: String) -> Line {
  Line(spans: [span_plain(content)], alignment: text.Left)
}

/// Line from spans with explicit alignment.
pub fn line_aligned(spans: List(Span), alignment: text.Alignment) -> Line {
  Line(spans: spans, alignment: alignment)
}

/// Bold span (default colors + bold modifier).
pub fn span_bold(content: String) -> Span {
  Span(
    content: content,
    fg: style.Default,
    bg: style.Default,
    modifier: style.bold(),
    link: "",
  )
}

/// Italic span (default colors + italic modifier).
pub fn span_italic(content: String) -> Span {
  Span(
    content: content,
    fg: style.Default,
    bg: style.Default,
    modifier: style.italic(),
    link: "",
  )
}

/// Dim span (default colors + dim modifier).
pub fn span_dim(content: String) -> Span {
  Span(
    content: content,
    fg: style.Default,
    bg: style.Default,
    modifier: style.dim(),
    link: "",
  )
}

/// Underline span (default colors + underline modifier).
pub fn span_underline(content: String) -> Span {
  Span(
    content: content,
    fg: style.Default,
    bg: style.Default,
    modifier: style.underline(),
    link: "",
  )
}

/// Total cell width of a line (sum of span widths).
pub fn line_width(l: Line) -> Int {
  list.fold(l.spans, 0, fn(acc, sp) { acc + span_width(sp) })
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render a line into the buffer at `pos`, clipped to `max_width` cells.
/// Each span is drawn with its own fg/bg/modifier. Spans beyond max_width
/// are silently dropped; a span that straddles the boundary is truncated.
/// The line's `alignment` field shifts the start position within the available width.
pub fn render_line(
  buf: buffer.Buffer,
  pos: geometry.Position,
  l: Line,
  max_width: Int,
) -> buffer.Buffer {
  case max_width <= 0 {
    True -> buf
    False -> {
      let content_width = line_width(l)
      let offset = case l.alignment {
        text.Left -> 0
        text.Right -> int.max(0, max_width - content_width)
        text.Center -> int.max(0, { max_width - content_width } / 2)
      }
      let start_x = pos.x + offset
      render_spans(buf, pos, l.spans, start_x, pos.x + max_width)
    }
  }
}

fn render_spans(
  buf: buffer.Buffer,
  pos: geometry.Position,
  spans: List(Span),
  x: Int,
  x_end: Int,
) -> buffer.Buffer {
  case spans {
    [] -> buf
    [sp, ..rest] -> {
      case x >= x_end {
        True -> buf
        False -> {
          let avail = x_end - x
          let content = text.truncate(sp.content, avail, "")
          let w = text.cell_width(content)
          let buf2 =
            buffer.set_string_linked(
              buf,
              geometry.Position(x: x, y: pos.y),
              content,
              sp.fg,
              sp.bg,
              sp.modifier,
              sp.link,
            )
          render_spans(buf2, pos, rest, x + w, x_end)
        }
      }
    }
  }
}
