/// Paragraph widget: text wrapping, alignment, styling.
/// Also supports `span.Line` for inline mixed-style text via `paragraph_new_lines`.
import etui/buffer
import etui/geometry
import etui/span
import etui/style
import etui/text.{type Alignment, Left}

/// Word-wrapping text block with alignment and styling.
pub type Paragraph {
  Paragraph(
    text: String,
    alignment: Alignment,
    fg: style.Color,
    bg: style.Color,
    modifier: style.Modifier,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New paragraph with left-aligned text and default colors.
pub fn paragraph_new(text: String) -> Paragraph {
  Paragraph(
    text: text,
    alignment: Left,
    fg: style.Default,
    bg: style.Default,
    modifier: style.none(),
  )
}

/// Set text alignment (Left, Center, Right).
pub fn with_alignment(p: Paragraph, alignment: Alignment) -> Paragraph {
  Paragraph(..p, alignment: alignment)
}

/// Apply a style (colors + modifier) to the paragraph text.
pub fn with_style(p: Paragraph, s: style.Style) -> Paragraph {
  Paragraph(..p, fg: s.fg, bg: s.bg, modifier: s.modifier)
}

// ─────────────────────────────────────────────────────────────────
// Span-aware variant

/// Paragraph backed by styled span lines rather than a plain string.
/// Use `paragraph_new_lines` to construct, `render_lines_styled` to render.
pub type SpanParagraph {
  SpanParagraph(lines: List(span.Line))
}

/// Build a `SpanParagraph` from a list of `span.Line` values.
///
/// ```gleam
/// paragraph.paragraph_new_lines([
///   span.line_new([span.span_plain("normal "), span.span_styled("bold", style.bold_style())]),
///   span.line_plain("second line"),
/// ])
/// |> paragraph.render_lines_styled(buf, area, _)
/// ```
pub fn paragraph_new_lines(lines: List(span.Line)) -> SpanParagraph {
  SpanParagraph(lines: lines)
}

/// Render a `SpanParagraph` into `area`. Lines beyond area height are clipped.
pub fn render_lines_styled(
  buf: buffer.Buffer,
  area: geometry.Rect,
  para: SpanParagraph,
) -> buffer.Buffer {
  render_styled(buf, area, para.lines)
}

/// Render a list of `span.Line` values, one per row, into `area`.
/// Each `Line` is drawn with per-span styles. Lines beyond area height
/// are clipped; the list may be shorter than the area (remaining rows unchanged).
pub fn render_styled(
  buf: buffer.Buffer,
  area: geometry.Rect,
  lines: List(span.Line),
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> render_span_rows(buf, area, lines, 0)
  }
}

fn render_span_rows(
  buf: buffer.Buffer,
  area: geometry.Rect,
  lines: List(span.Line),
  row: Int,
) -> buffer.Buffer {
  case lines {
    [] -> buf
    [line, ..rest] ->
      case row >= area.size.height {
        True -> buf
        False -> {
          let pos =
            geometry.Position(x: area.position.x, y: area.position.y + row)
          let buf2 = span.render_line(buf, pos, line, area.size.width)
          render_span_rows(buf2, area, rest, row + 1)
        }
      }
  }
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render paragraph into buffer at `area`. Word-wraps to area width.
/// Rows beyond area height are clipped. Short lines are padded to area width.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  para: Paragraph,
) -> buffer.Buffer {
  case area.size.width <= 0 || area.size.height <= 0 {
    True -> buf
    False -> {
      // Wrap text to area width
      let lines = text.wrap(para.text, area.size.width)
      // Render lines up to area height
      render_lines(buf, area, para, lines, 0)
    }
  }
}

fn render_lines(
  buf: buffer.Buffer,
  area: geometry.Rect,
  para: Paragraph,
  lines: List(String),
  line_idx: Int,
) -> buffer.Buffer {
  case lines {
    [] -> buf
    [line, ..rest] -> {
      case line_idx >= area.size.height {
        True -> buf
        False -> {
          let y = area.position.y + line_idx
          let aligned_line = text.align(line, area.size.width, para.alignment)
          let buf_new =
            buffer.set_string(
              buf,
              geometry.Position(x: area.position.x, y: y),
              aligned_line,
              para.fg,
              para.bg,
              para.modifier,
            )
          render_lines(buf_new, area, para, rest, line_idx + 1)
        }
      }
    }
  }
}
