import emoji_width_fixture
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/list
import gleam/string
import gleeunit/should

fn examples() {
  [
    #("☺", 1),
    #("☺\u{FE0F}", 2),
    #("❤\u{FE0F}", 2),
    #("☀\u{FE0F}", 2),
    #("©\u{FE0F}", 2),
    #("☕\u{FE0E}", 1),
    #("⌚\u{FE0E}", 1),
    #("🚀\u{FE0E}", 2),
    #("👩‍💻", 2),
    #("#\u{FE0F}\u{20E3}", 2),
    #("1\u{FE0F}\u{20E3}", 2),
    #("1\u{FE0E}", 1),
    #("A\u{FE0F}", 1),
    #("漢\u{FE0E}", 2),
    #("\u{0301}\u{FE0F}", 0),
    #("☺\u{0301}\u{FE0F}", 1),
    #("✦", 1),
    #("⭐", 2),
    #("🅰\u{FE0F}", 2),
  ]
}

pub fn emoji_selectors_change_width_only_for_supported_bases_test() {
  list.each(examples(), fn(pair) {
    let #(grapheme, width) = pair
    #(grapheme, text.grapheme_cell_width(grapheme))
    |> should.equal(#(grapheme, width))
    text.cell_width(grapheme) |> should.equal(width)
  })
}

fn check_row(buf: buffer.Buffer, g: String, width: Int, y: Int) {
  buffer.cell_symbol(buffer.get_cell(buf, geometry.Position(0, y)))
  |> should.equal(g)
  buffer.get_cell(buf, geometry.Position(0, y)).content
  |> should.equal(buffer.Content(g, width))
  buffer.cell_symbol(buffer.get_cell(buf, geometry.Position(width, y)))
  |> should.equal("x")
  case width {
    2 ->
      buffer.is_continuation(buffer.get_cell(buf, geometry.Position(1, y)))
      |> should.equal(True)
    _ -> Nil
  }
}

pub fn buffer_writes_and_bulk_fill_keep_selected_graphemes_intact_test() {
  list.each(examples(), fn(pair) {
    let #(g, width) = pair
    case width {
      0 -> Nil
      _ -> {
        let area = geometry.rect_new(0, 0, 4, 2)
        let st = style.default_style()
        let written =
          buffer.buffer_new(area)
          |> buffer.set_string(geometry.Position(0, 0), g <> "x", st)
        check_row(written, g, width, 0)
        let filled = buffer.buffer_new_filled(area, g <> "x", st)
        check_row(filled, g, width, 0)
        check_row(filled, g, width, 1)
      }
    }
  })
}

pub fn selected_wide_graphemes_are_clipped_at_row_end_test() {
  let area = geometry.rect_new(0, 0, 1, 1)
  let st = style.default_style()
  list.each(["☺\u{FE0F}", "1\u{FE0F}\u{20E3}"], fn(g) {
    let written =
      buffer.buffer_new(area)
      |> buffer.set_string(geometry.Position(0, 0), g, st)
    let filled = buffer.buffer_new_filled(area, g, st)
    buffer.cell_symbol(buffer.get_cell(written, geometry.Position(0, 0)))
    |> should.equal(" ")
    buffer.cell_symbol(buffer.get_cell(filled, geometry.Position(0, 0)))
    |> should.equal(" ")
  })
}

pub fn truncation_preserves_selected_graphemes_and_cell_limits_test() {
  text.truncate("☺\u{FE0F}x", 2, "") |> should.equal("☺\u{FE0F}")
  text.truncate("☺\u{FE0F}x", 1, "") |> should.equal("")
  text.truncate("☕\u{FE0E}x", 1, "") |> should.equal("☕\u{FE0E}")
}

// The fixture comes from official Unicode data, not the implementation table.
pub fn all_unicode_emoji_variations_match_the_independent_oracle_test() {
  list.each(emoji_width_fixture.bases(), fn(pair) {
    let #(base, text_width) = pair
    list.each(
      [#(base <> "\u{FE0E}", text_width), #(base <> "\u{FE0F}", 2)],
      fn(sequence) {
        let #(g, width) = sequence
        #(g, text.cell_width(g)) |> should.equal(#(g, width))
        let area = geometry.rect_new(0, 0, 4, 1)
        let st = style.default_style()
        let written =
          buffer.buffer_new(area)
          |> buffer.set_string(geometry.Position(0, 0), g <> "x", st)
        check_row(written, g, width, 0)
        check_row(buffer.buffer_new_filled(area, g <> "x", st), g, width, 0)
      },
    )
  })
}

pub fn selected_wide_graphemes_fill_an_exactly_fitting_row_test() {
  let area = geometry.rect_new(0, 0, 2, 1)
  let st = style.default_style()
  list.each(["☺\u{FE0F}", "1\u{FE0F}\u{20E3}"], fn(g) {
    let written =
      buffer.buffer_new(area)
      |> buffer.set_string(geometry.Position(0, 0), g, st)
    list.each([written, buffer.buffer_new_filled(area, g, st)], fn(buf) {
      buffer.get_cell(buf, geometry.Position(0, 0)).content
      |> should.equal(buffer.Content(g, 2))
      buffer.is_continuation(buffer.get_cell(buf, geometry.Position(1, 0)))
      |> should.equal(True)
    })
  })
}

pub fn unsupported_neighbours_ignore_emoji_selectors_test() {
  let bases = list.map(emoji_width_fixture.bases(), fn(pair) { pair.0 })
  list.each(bases, fn(base) {
    let assert [cp] = string.to_utf_codepoints(base)
    let n = string.utf_codepoint_to_int(cp)
    list.each([n - 1, n + 1], fn(neighbour) {
      let assert Ok(cp) = string.utf_codepoint(neighbour)
      let g = string.from_utf_codepoints([cp])
      case list.contains(bases, g) {
        True -> Nil
        False ->
          list.each(["\u{FE0E}", "\u{FE0F}"], fn(selector) {
            #(g <> selector, text.cell_width(g <> selector))
            |> should.equal(#(g <> selector, text.cell_width(g)))
          })
      }
    })
  })
}
