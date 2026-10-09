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
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

/// A styled text fragment: string content + display style + optional hyperlink.
pub type Span {
  Span(
    content: String,
    style: style.Style,
    /// OSC 8 hyperlink URI. Empty string = no link.
    link: String,
  )
}

/// A single terminal row composed of styled spans.
pub type Line {
  Line(spans: List(Span), alignment: text.Alignment)
}

/// Several lines of styled text.
///
/// `Line` is one row and never wraps; `Text` is a block that does. Until this
/// existed, wrapping only worked on a plain `String`, so any text that needed
/// both mixed styles and reflowing, a log viewer or rendered markdown, could
/// not have both.
pub type Text {
  Text(lines: List(Line))
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// Span with default terminal colors and no modifier.
pub fn span_plain(content: String) -> Span {
  Span(content: content, style: style.default_style(), link: "")
}

/// Span with explicit style applied.
pub fn span_styled(content: String, s: style.Style) -> Span {
  Span(content: content, style: s, link: "")
}

/// Span with an OSC 8 clickable hyperlink.
/// Terminals that support OSC 8 (iTerm2, Kitty, VTE, Windows Terminal) will
/// render the text as a clickable link. Others display it as plain text.
///
/// ```gleam
/// span.span_link("docs.gleam.run", "https://docs.gleam.run")
/// ```
pub fn span_link(content: String, uri: String) -> Span {
  Span(content: content, style: style.default_style(), link: uri)
}

/// Add an OSC 8 hyperlink URI to an existing span.
pub fn with_link(sp: Span, uri: String) -> Span {
  Span(..sp, link: uri)
}

/// Set foreground color on a span.
pub fn span_fg(sp: Span, color: style.Color) -> Span {
  Span(..sp, style: style.with_fg(sp.style, color))
}

/// Set background color on a span.
pub fn span_bg(sp: Span, color: style.Color) -> Span {
  Span(..sp, style: style.with_bg(sp.style, color))
}

/// Add a modifier to a span.
pub fn span_modifier(sp: Span, modifier: style.Modifier) -> Span {
  Span(..sp, style: style.add_modifier(sp.style, modifier))
}

/// Colour the underline of a span independently of its text.
pub fn span_underline_color(sp: Span, color: style.Color) -> Span {
  Span(..sp, style: style.with_underline_color(sp.style, color))
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
    style: style.new(style.Default, style.Default, style.bold()),
    link: "",
  )
}

/// Italic span (default colors + italic modifier).
pub fn span_italic(content: String) -> Span {
  Span(
    content: content,
    style: style.new(style.Default, style.Default, style.italic()),
    link: "",
  )
}

/// Dim span (default colors + dim modifier).
pub fn span_dim(content: String) -> Span {
  Span(
    content: content,
    style: style.new(style.Default, style.Default, style.dim()),
    link: "",
  )
}

/// Underline span (default colors + underline modifier).
pub fn span_underline(content: String) -> Span {
  Span(
    content: content,
    style: style.new(style.Default, style.Default, style.underline()),
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
              sp.style,
              sp.link,
            )
          render_spans(buf2, pos, rest, x + w, x_end)
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Wrapping

/// Text from a single unstyled string, split on newlines.
pub fn text_plain(content: String) -> Text {
  Text(
    lines: content
    |> text.normalise_newlines
    |> string.split("\n")
    |> list.map(line_plain),
  )
}

/// Text from lines.
pub fn text_new(lines: List(Line)) -> Text {
  Text(lines: lines)
}

/// Total rows.
pub fn text_height(t: Text) -> Int {
  list.length(t.lines)
}

/// Wrap every line to `width` cells, keeping each span's style.
///
/// ```gleam
/// span.line_new([span.span_bold("ERROR"), span.span_plain(" disk full")])
/// |> span.text_new([_])
/// |> span.wrap(12)
/// // ERROR disk   <- still bold
/// // full
/// ```
pub fn wrap(t: Text, width: Int) -> Text {
  case width <= 0 {
    True -> Text(lines: [])
    False -> Text(lines: list.flat_map(t.lines, wrap_line(_, width)))
  }
}

/// Wrap one line into as many as it takes.
///
/// Words are the unit, as in `text.wrap`, and a word wider than the line is
/// broken across rows rather than left to overflow. A word never loses its
/// style by being moved to another row, which is the whole point: the styles
/// travel with the words rather than with the columns they happened to be in.
pub fn wrap_line(l: Line, width: Int) -> List(Line) {
  case width <= 0 {
    True -> []
    False ->
      case tokenise(l.spans, []) {
        // An empty line stays one empty line rather than vanishing.
        [] -> [Line(spans: [], alignment: l.alignment)]
        words -> pack(words, width, l.alignment, 0, [], [])
      }
  }
}

// A word, which may be made of pieces from more than one span: "etui.log"
// styled one way followed immediately by "," styled another is a single word
// and must never be split by the wrapper.
//
// Splitting each span on spaces independently and rejoining with spaces put a
// space between those two, inventing whitespace the source never had.
type Piece {
  Piece(content: String, style: Span)
}

// `sep` is the style of the space that preceded this word in the source. The
// wrapper drops that space at a line break and re-emits it between words on
// the same row, and it has to come back styled as it was: an unstyled space
// punches a hole in a highlighted run, and a space that borrows the next
// word's style draws that word's underline one cell early.
type Word {
  Word(sep: Span, pieces: List(Piece))
}

fn word_width(w: Word) -> Int {
  list.fold(w.pieces, 0, fn(acc, p) { acc + text.cell_width(p.content) })
}

fn word_text(w: Word) -> String {
  string.concat(list.map(w.pieces, fn(p) { p.content }))
}

fn tokenise(spans: List(Span), acc: List(Word)) -> List(Word) {
  let blank = span_plain("")
  let #(words, pending, pending_sep) = tokenise_loop(spans, [], blank, [])
  let all = case pending {
    [] -> words
    _ -> [Word(sep: pending_sep, pieces: list.reverse(pending)), ..words]
  }
  let _ = acc
  list.reverse(all)
}

// `pending` is the word being built, newest piece first. A span boundary only
// ends a word when there is a space at it.
fn tokenise_loop(
  spans: List(Span),
  pending: List(Piece),
  pending_sep: Span,
  done: List(Word),
) -> #(List(Word), List(Piece), Span) {
  case spans {
    [] -> #(done, pending, pending_sep)
    [sp, ..rest] -> {
      let #(next_pending, next_sep, next_done) =
        absorb(
          string.split(sp.content, " "),
          sp,
          pending,
          pending_sep,
          done,
          True,
        )
      tokenise_loop(rest, next_pending, next_sep, next_done)
    }
  }
}

fn absorb(
  parts: List(String),
  sp: Span,
  pending: List(Piece),
  pending_sep: Span,
  done: List(Word),
  first: Bool,
) -> #(List(Piece), Span, List(Word)) {
  case parts {
    [] -> #(pending, pending_sep, done)
    [part, ..rest] -> {
      // Every part after the first was preceded by a space, so it starts a new
      // word; the first one continues whatever was already being built. That
      // space came out of `sp`, and the word now starting is the one that has
      // to carry it back.
      let #(carry, carry_sep, closed) = case first {
        True -> #(pending, pending_sep, done)
        False ->
          case pending {
            [] -> #([], sp, done)
            _ -> #([], sp, [
              Word(sep: pending_sep, pieces: list.reverse(pending)),
              ..done
            ])
          }
      }
      let grown = case part {
        "" -> carry
        _ -> [Piece(content: part, style: sp), ..carry]
      }
      absorb(rest, sp, grown, carry_sep, closed, False)
    }
  }
}

fn pack(
  words: List(Word),
  width: Int,
  alignment: text.Alignment,
  current_width: Int,
  current: List(Span),
  done: List(Line),
) -> List(Line) {
  case words {
    [] ->
      list.reverse([
        Line(spans: list.reverse(current), alignment: alignment),
        ..done
      ])
    [w, ..rest] -> {
      let this_width = word_width(w)
      let gap = case current {
        [] -> 0
        _ -> 1
      }
      case current_width + gap + this_width <= width {
        True ->
          pack(
            rest,
            width,
            alignment,
            current_width + gap + this_width,
            push_word(current, w, gap),
            done,
          )
        False ->
          case this_width <= width {
            // Starts the next row whole.
            True ->
              pack(
                rest,
                width,
                alignment,
                this_width,
                push_word([], w, 0),
                flush(current, alignment, done),
              )
            // Wider than any row: break it across rows. A word this long is
            // treated as one style, its first, rather than tracking where each
            // piece falls inside the break.
            False -> {
              let proto = case w.pieces {
                [Piece(style: st, ..), ..] -> st
                [] -> span_plain("")
              }
              let rows =
                break_word(word_text(w), width - current_width - gap, width)
              // The first piece fills what is left of the current row; it is
              // empty when not even one grapheme fits there.
              let #(fill, more) = case rows {
                [first, ..others] -> #(first, others)
                [] -> #("", [])
              }
              let closed = case fill {
                "" -> flush(current, alignment, done)
                _ ->
                  flush(
                    push(push_gap(current, w.sep, gap), fill, proto),
                    alignment,
                    done,
                  )
              }
              // Every piece but the last is a full row of its own. The last
              // stays open so the words after it can share its row.
              case list.reverse(more) {
                [last, ..before] ->
                  pack(
                    rest,
                    width,
                    alignment,
                    text.cell_width(last),
                    push([], last, proto),
                    list.fold(list.reverse(before), closed, fn(acc, row) {
                      flush(push([], row, proto), alignment, acc)
                    }),
                  )
                [] -> pack(rest, width, alignment, 0, [], closed)
              }
            }
          }
      }
    }
  }
}

// Push a whole word, piece by piece, so each keeps its own style.
fn push_word(current: List(Span), w: Word, gap: Int) -> List(Span) {
  let started = push_gap(current, w.sep, gap)
  list.fold(w.pieces, started, fn(acc, piece) {
    push(acc, piece.content, piece.style)
  })
}

fn push_gap(current: List(Span), sep: Span, gap: Int) -> List(Span) {
  case gap {
    0 -> current
    _ -> push(current, " ", sep)
  }
}

fn flush(
  current: List(Span),
  alignment: text.Alignment,
  done: List(Line),
) -> List(Line) {
  case current {
    // A row with nothing in it would draw as a blank line the text never had.
    [] -> done
    _ -> [Line(spans: list.reverse(current), alignment: alignment), ..done]
  }
}

// Append to the span being built when the style matches, so a wrapped line
// does not come back as one span per word.
fn push(current: List(Span), content: String, proto: Span) -> List(Span) {
  case current {
    [head, ..rest] ->
      case same_style(head, proto) {
        True -> [Span(..head, content: head.content <> content), ..rest]
        False -> [Span(..proto, content: content), ..current]
      }
    [] -> [Span(..proto, content: content)]
  }
}

fn same_style(a: Span, b: Span) -> Bool {
  a.style == b.style && a.link == b.link
}

// Cut a word wider than a row into rows, walking its graphemes once.
//
// The first row has `room` cells, because part of the current row is already
// taken, and may come back empty. Every later row has `width` cells. A row
// that is still empty always takes the grapheme in front of it, even one wider
// than the row, so every step either adds a grapheme or closes a row and the
// walk always ends. A zero-width grapheme fits wherever it lands and so stays
// with the grapheme before it.
fn break_word(content: String, room: Int, width: Int) -> List(String) {
  cut(string.to_graphemes(content), width, room, False, "", 0, [])
}

fn cut(
  graphemes: List(String),
  width: Int,
  limit: Int,
  later: Bool,
  row: String,
  used: Int,
  closed: List(String),
) -> List(String) {
  case graphemes {
    [] -> list.reverse([row, ..closed])
    [g, ..rest] -> {
      let w = text.grapheme_cell_width(g)
      case used + w <= limit || { later && row == "" } {
        True -> cut(rest, width, limit, later, row <> g, used + w, closed)
        False -> cut(graphemes, width, width, True, "", 0, [row, ..closed])
      }
    }
  }
}
