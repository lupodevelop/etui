import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/list
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
