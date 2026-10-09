import etui/buffer
import etui/geometry
import etui/style
import gleam/list
import gleeunit/should

fn frame(text: String) -> buffer.Buffer {
  buffer.buffer_new(geometry.rect_new(0, 0, 10, 2))
  |> buffer.set_string(geometry.Position(0, 0), text, style.default_style())
}

pub fn the_same_buffer_has_no_diff_test() {
  let f = frame("hello")
  buffer.diff(f, f) |> should.equal([])
}

pub fn equal_but_distinct_buffers_have_no_diff_test() {
  buffer.diff(frame("hello"), frame("hello")) |> should.equal([])
}

pub fn a_changed_buffer_still_diffs_test() {
  buffer.diff(frame("hello"), frame("help!"))
  |> list.is_empty
  |> should.equal(False)
}
