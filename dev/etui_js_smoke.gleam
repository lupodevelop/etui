/// JS smoke test, pure geometry, buffer, and widget operations.
/// Run: gleam run --target javascript -m etui_js_smoke
import etui/buffer
import etui/geometry.{Fill, Length, Percentage, rect_new}
import etui/span
import etui/style
import etui/widgets/paragraph
import gleam/io
import gleam/list
import gleam/string

fn check(label: String, cond: Bool) -> Nil {
  case cond {
    True -> io.println("  PASS: " <> label)
    False -> panic as { "FAIL: " <> label }
  }
}

pub fn main() -> Nil {
  io.println("etui JS smoke test")
  io.println(string.repeat("─", 40))

  // geometry
  let r = rect_new(0, 0, 80, 24)
  check("rect_new width=80", r.size.width == 80)
  check("rect_new height=24", r.size.height == 24)

  let sizes = geometry.resolve_sizes(100, [Length(20), Percentage(50), Fill])
  check("resolve_sizes length=3", list.length(sizes) == 3)
  check("resolve_sizes Length=20", list.first(sizes) == Ok(20))
  check("resolve_sizes Fill=30", list.last(sizes) == Ok(30))

  // buffer
  let area = rect_new(0, 0, 10, 3)
  let buf = buffer.buffer_new(area)
  check("buffer_new width=10", buffer.area(buf).size.width == 10)

  let pos = geometry.Position(2, 1)
  let buf2 =
    buffer.set_string(
      buf,
      pos,
      "hi",
      style.Default,
      style.Default,
      style.none(),
    )
  let cell = buffer.get_cell(buf2, pos)
  let cell_sym = case cell.content {
    buffer.Content(s, _) -> s
    buffer.Continuation -> ""
  }
  check("set_string cell(2,1)='h'", cell_sym == "h")

  let same = buffer.diff_to_ansi(buf, buf)
  check("diff_to_ansi identical=''", same == "")

  let changed = buffer.diff_to_ansi(buf, buf2)
  check("diff_to_ansi changed non-empty", string.length(changed) > 0)

  let full = buffer.to_ansi(buf2)
  check("to_ansi non-empty", string.length(full) > 0)

  // paragraph
  let parea = rect_new(0, 0, 20, 5)
  let pbuf = buffer.buffer_new(parea)
  let p = paragraph.paragraph_new("hello")
  let pbuf2 = paragraph.render(pbuf, parea, p)
  let pcell = buffer.get_cell(pbuf2, geometry.Position(0, 0))
  let pcell_sym = case pcell.content {
    buffer.Content(s, _) -> s
    buffer.Continuation -> ""
  }
  check("paragraph 'hello' at (0,0)='h'", pcell_sym == "h")

  // span line
  let s = span.span_plain("world")
  let line = span.line_new([s])
  let sbuf = span.render_line(pbuf, geometry.Position(0, 1), line, 20)
  let scell = buffer.get_cell(sbuf, geometry.Position(0, 1))
  let scell_sym = case scell.content {
    buffer.Content(s, _) -> s
    buffer.Continuation -> ""
  }
  check("span render_line 'world' at (0,1)='w'", scell_sym == "w")

  io.println(string.repeat("─", 40))
  io.println("All smoke tests passed.")
}
