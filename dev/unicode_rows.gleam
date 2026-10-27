/// Shared deterministic row corpus and independent cell model.
/// `main` prints canonical cells for dev/check_unicode_rows.py.
import etui/buffer
import etui/geometry.{Position}
import etui/style
import gleam/int
import gleam/io
import gleam/list
import gleam/string

pub type Outcome {
  Outcome(id: String, actual: List(buffer.Cell), expected: List(buffer.Cell))
}

fn indices(n: Int) {
  list.index_map(list.repeat(Nil, n), fn(_, i) { i })
}

fn next(seed: Int) {
  { seed * 1_664_525 + 1_013_904_223 } % 2_147_483_647
}

fn row_text(seed: Int) {
  case seed {
    253 -> "☺\u{200D}\u{0301}\u{200D}x"
    254 -> "☺\u{200D}\u{0301}\u{20E3}x"
    255 -> "☺\u{200D}\u{20E3}x"
    _ -> generated_row(seed)
  }
}

fn generated_row(seed: Int) {
  let atoms = [
    "a", "b", "e\u{0301}", "漢", "界", "☺", "☺\u{FE0F}", "☕\u{FE0E}", "👩‍💻",
    "1\u{FE0F}\u{20E3}", "#\u{FE0F}\u{20E3}", "🇮🇹", "\u{0301}", "\u{200B}",
    "\u{FE0F}", "\u{FEFF}", "\u{200D}", "\r\n", "\t",
  ]
  let #(_, pieces) =
    list.map_fold(indices(12), seed + 1, fn(s, _) {
      let s = next(s)
      let assert Ok(atom) = list.first(list.drop(atoms, s % list.length(atoms)))
      #(s, atom)
    })
  string.join(pieces, "")
}

// Corpus-specific oracle: fixed widths for its bases, no production width
// calls or production Unicode table. Runtime grapheme segmentation is shared;
// comparing the emitted cells separately detects differences between runtimes.
fn expected_width(g: String) -> Int {
  let assert [cp, ..rest] = string.to_utf_codepoints(g)
  let base = string.utf_codepoint_to_int(cp)
  let selector = case rest {
    [cp, ..] -> string.utf_codepoint_to_int(cp)
    [] -> 0
  }
  case base {
    0x263A if selector == 0xFE0F -> 2
    0x2615 if selector == 0xFE0E -> 1
    0x23 | 0x31 if selector == 0xFE0F -> 2
    0x61 | 0x62 | 0x65 | 0x78 | 0x23 | 0x31 | 0x263A -> 1
    0x6F22 | 0x754C | 0x2615 | 0x1F469 | 0x1F4BB | 0x1F1EE | 0x1F1F9 -> 2
    0x0301 | 0x200B | 0x200D | 0xFE0F | 0xFEFF | 0x0D | 0x0A | 0x09 -> 0
    _ -> panic as "Corpus contains a base without an oracle width"
  }
}

// GB9 also applies to combining tails that OTP may return separately after
// a ZWJ. This corpus oracle joins those tails before placing expected cells.
fn model_clusters(value: String) {
  list.fold(string.to_graphemes(value), [], fn(rev, g) {
    case rev {
      [prev, ..rest] -> {
        let extension =
          string.starts_with(g, "\u{0301}")
          || string.starts_with(g, "\u{FE0F}")
          || string.starts_with(g, "\u{200D}")
          || string.starts_with(g, "\u{20E3}")
        case string.ends_with(prev, "\u{200D}") && extension {
          True -> [prev <> g, ..rest]
          False -> [g, ..rev]
        }
      }
      [] -> [g]
    }
  })
  |> list.reverse
}

fn model_row(
  gs: List(String),
  room: Int,
  st: style.Style,
  link: String,
  empty: buffer.Cell,
) -> List(buffer.Cell) {
  case room <= 0 {
    True -> []
    False ->
      case gs {
        [] -> list.repeat(empty, room)
        [g, ..rest] ->
          case expected_width(g) {
            0 -> model_row(rest, room, st, link, empty)
            w if w > room -> list.repeat(empty, room)
            2 -> [
              buffer.Cell(buffer.Content(g, 2), st, link),
              buffer.Cell(buffer.Continuation, st, ""),
              ..model_row(rest, room - 2, st, link, empty)
            ]
            _ -> [
              buffer.Cell(buffer.Content(g, 1), st, link),
              ..model_row(rest, room - 1, st, link, empty)
            ]
          }
      }
  }
}

fn cells(buf: buffer.Buffer) {
  let area = buffer.area(buf)
  list.flat_map(indices(area.size.height), fn(y) {
    list.map(indices(area.size.width), fn(x) {
      buffer.get_cell(buf, Position(area.position.x + x, area.position.y + y))
    })
  })
}

fn scenario(seed: Int, start: Int) -> List(Outcome) {
  let width = seed % 13
  let origin = case seed % 2 {
    0 -> -2
    _ -> 3
  }
  let area = geometry.rect_new(origin, 2, width, 3)
  let pos = Position(origin + start, 3)
  let st =
    style.new(style.Rgb(seed % 256, 40, 120), style.Indexed(4), style.bold())
    |> style.with_underline_color(style.Indexed(2))
    |> style.add_modifier(style.underline())
    |> style.resolve
  let value = row_text(seed)
  let gs = model_clusters(value)
  let id = int.to_string(seed) <> "/" <> int.to_string(start)
  let link = "https://example.test/" <> int.to_string(seed)
  let empty = buffer.Cell(buffer.Content(".", 1), style.default_style(), "")
  let original =
    buffer.buffer_new_filled(
      area,
      string.repeat(".", width),
      style.default_style(),
    )
  let direct = buffer.set_string_linked(original, pos, value, st, link)
  let expected = case start < 0 || start >= width {
    True -> list.repeat(empty, width * 3)
    False ->
      list.append(
        list.repeat(empty, width + start),
        list.append(
          model_row(gs, width - start, st, link, empty),
          list.repeat(empty, width),
        ),
      )
  }
  let filled = buffer.buffer_new_filled(area, value, st)
  let row = model_row(gs, width, st, "", buffer.empty_cell())
  let bulk_expected = list.flatten(list.repeat(row, 3))
  [
    Outcome(id <> "/linked", cells(direct), expected),
    Outcome(id <> "/bulk", cells(filled), bulk_expected),
    Outcome(id <> "/original", cells(original), list.repeat(empty, width * 3)),
  ]
}

pub fn outcomes() -> List(Outcome) {
  list.flat_map(indices(256), fn(seed) {
    let width = seed % 13
    list.flat_map(list.unique([-1, 0, width - 1, width]), scenario(seed, _))
  })
}

fn encoded(s: String) {
  s
  |> string.to_utf_codepoints
  |> list.map(fn(cp) { int.to_string(string.utf_codepoint_to_int(cp)) })
  |> string.join(":")
}

fn canonical(cell: buffer.Cell) {
  let content = case cell.content {
    buffer.Continuation -> "T"
    buffer.Content(g, w) -> "C" <> int.to_string(w) <> ":" <> encoded(g)
  }
  let st = cell.style
  content
  <> "/"
  <> encoded(style.ansi_fg(st.fg))
  <> "/"
  <> encoded(style.ansi_bg(st.bg))
  <> "/"
  <> encoded(style.ansi_modifier(st.modifier))
  <> "/"
  <> encoded(style.ansi_modifier(st.sub_modifier))
  <> "/"
  <> encoded(style.ansi_underline_color(st.underline_color))
  <> "/"
  <> encoded(cell.link)
}

pub fn main() {
  list.each(outcomes(), fn(outcome) {
    io.println(
      "ROW "
      <> outcome.id
      <> " "
      <> string.join(list.map(outcome.actual, canonical), "|"),
    )
  })
}
