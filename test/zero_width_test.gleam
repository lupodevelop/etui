import etui/buffer
import etui/geometry.{Position}
import etui/span
import etui/style
import etui/text
import etui/widgets/input
import etui/widgets/textarea
import gleam/list
import gleeunit/should

fn standalone_zero_width() {
  [
    "\u{0301}",
    "\u{200B}",
    "\u{200C}",
    "\u{200D}",
    "\u{FE0E}",
    "\u{FE0F}",
    "\u{FEFF}",
    "\u{1160}",
  ]
}

pub fn standalone_zero_width_clusters_do_not_advance_or_replace_cells_test() {
  let area = geometry.rect_new(3, 2, 4, 2)
  let original = buffer.buffer_new_filled(area, "....", style.default_style())
  let st = style.bold_style()
  list.each(standalone_zero_width(), fn(zero) {
    list.each([0, 3], fn(offset) {
      let pos = Position(3 + offset, 2)
      let unchanged = buffer.set_string_linked(original, pos, zero, st, "link")
      let actual =
        buffer.set_string_linked(original, pos, zero <> "x", st, "link")
      let expected = buffer.set_string_linked(original, pos, "x", st, "link")
      list.each([2, 3], fn(y) {
        list.each([3, 4, 5, 6], fn(x) {
          buffer.get_cell(unchanged, Position(x, y))
          |> should.equal(buffer.get_cell(original, Position(x, y)))
          buffer.get_cell(actual, Position(x, y))
          |> should.equal(buffer.get_cell(expected, Position(x, y)))
        })
      })
    })
  })
}

pub fn bulk_fill_skips_standalone_zero_width_clusters_test() {
  let area = geometry.rect_new(0, 0, 4, 2)
  let st = style.bold_style()
  list.each(standalone_zero_width(), fn(zero) {
    let actual = buffer.buffer_new_filled(area, zero <> "x", st)
    let expected = buffer.buffer_new_filled(area, "x", st)
    list.each([0, 1], fn(y) {
      list.each([0, 1, 2, 3], fn(x) {
        buffer.get_cell(actual, Position(x, y))
        |> should.equal(buffer.get_cell(expected, Position(x, y)))
      })
    })
  })
}

pub fn combining_marks_attached_to_a_visible_base_are_preserved_test() {
  let area = geometry.rect_new(0, 0, 3, 1)
  let st = style.bold_style()
  let g = "e\u{0301}\u{0308}"
  let written =
    buffer.buffer_new(area)
    |> buffer.set_string(Position(0, 0), g <> "x", st)
  list.each([written, buffer.buffer_new_filled(area, g <> "x", st)], fn(buf) {
    buffer.get_cell(buf, Position(0, 0)).content
    |> should.equal(buffer.Content(g, 1))
    buffer.cell_symbol(buffer.get_cell(buf, Position(1, 0)))
    |> should.equal("x")
  })
}

pub fn combining_tails_after_a_joiner_stay_with_the_visible_base_test() {
  let st = style.bold_style()
  list.each(
    [
      "☺\u{200D}\u{0301}\u{200D}",
      "☺\u{200D}\u{0301}\u{20E3}",
      "☺\u{200D}\u{20E3}",
      "☺\u{200D}\u{1AB0}",
    ],
    fn(g) {
      text.graphemes(g) |> should.equal([g])
      text.cell_width(g) |> should.equal(1)
      let wrapped = span.wrap(span.text_plain(g <> "x"), 1)
      list.map(wrapped.lines, fn(line) {
        list.fold(line.spans, "", fn(acc, sp) { acc <> sp.content })
      })
      |> should.equal([g, "x"])
      text.truncate(g <> "x", 1, "") |> should.equal(g)
      list.each([1, 4], fn(width) {
        let area = geometry.rect_new(0, 0, width, 1)
        let written =
          buffer.buffer_new(area)
          |> buffer.set_string(Position(0, 0), g <> "x", st)
        list.each(
          [written, buffer.buffer_new_filled(area, g <> "x", st)],
          fn(buf) {
            buffer.get_cell(buf, Position(0, 0)).content
            |> should.equal(buffer.Content(g, 1))
            case width > 1 {
              True ->
                buffer.cell_symbol(buffer.get_cell(buf, Position(1, 0)))
                |> should.equal("x")
              False -> Nil
            }
          },
        )
      })
    },
  )
}

pub fn editing_after_a_joiner_cluster_preserves_the_following_text_test() {
  let g = "☺\u{200D}\u{0301}\u{200D}"
  let state = input.InputState(g <> "x", 1)
  input.insert_char(input.input_new(""), state, "b").value
  |> should.equal(g <> "bx")
  input.backspace(state).value |> should.equal("x")
  let origin = input.InputState(g <> "x", 0)
  input.move_cursor_right(origin).cursor |> should.equal(1)
  let area = geometry.rect_new(0, 0, 2, 1)
  let rendered =
    input.render(
      buffer.buffer_new(area),
      area,
      input.input_new(""),
      input.InputState(g <> "x", 2),
    )
  buffer.cell_symbol(buffer.get_cell(rendered, Position(0, 0)))
  |> should.equal("x")
}

pub fn multiline_editing_uses_the_same_cluster_boundaries_test() {
  let g = "☺\u{200D}\u{0301}\u{200D}"
  let state = textarea.TextAreaState([g <> "x"], 1, 0)
  let widget = textarea.textarea_new()
  textarea.insert_char(widget, state, "b").lines |> should.equal([g <> "bx"])
  textarea.backspace(state).lines |> should.equal(["x"])
  textarea.newline(widget, state).lines |> should.equal([g, "x"])
}
