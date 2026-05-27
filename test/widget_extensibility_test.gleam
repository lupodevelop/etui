/// Tests for extensible widget system and new APIs.
/// Validates: custom widgets, composition, stateful/animated widgets,
/// input editing ops, list/table overflow fix, text.wrap with \n,
/// style.Indexed(>15), block.with_bg_fill, popup, statusbar.
import etui/buffer
import etui/geometry.{Position, Rect, Size}
import etui/span
import etui/style
import etui/text
import etui/widget
import etui/widgets/block
import etui/widgets/input as ginput
import etui/widgets/list as glist
import etui/widgets/paragraph
import etui/widgets/popup as gpopup
import etui/widgets/statusbar as gsbar
import gleeunit/should

// ─────────────────────────────────────────────────────────────────
// Helpers

fn read_row(buf: buffer.Buffer, y: Int, x: Int, n: Int) -> String {
  do_read_row(buf, y, x, x + n, "")
}

fn do_read_row(
  buf: buffer.Buffer,
  y: Int,
  x: Int,
  x_end: Int,
  acc: String,
) -> String {
  case x >= x_end {
    True -> acc
    False -> {
      let sym = buffer.cell_symbol(buffer.get_cell(buf, Position(x: x, y: y)))
      do_read_row(buf, y, x + 1, x_end, acc <> sym)
    }
  }
}

fn make_buf(w: Int, h: Int) -> buffer.Buffer {
  buffer.buffer_new(Rect(
    position: Position(x: 0, y: 0),
    size: Size(width: w, height: h),
  ))
}

// ─────────────────────────────────────────────────────────────────
// Custom widget: any fn(Buffer, Rect) -> Buffer qualifies

pub fn custom_widget_is_a_widget_test() {
  let buf = make_buf(10, 1)
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 10, height: 1))
  let w: widget.Widget = fn(b, a) {
    paragraph.render(b, a, paragraph.paragraph_new("hello"))
  }
  let result = w(buf, area)
  read_row(result, 0, 0, 5) |> should.equal("hello")
}

// ─────────────────────────────────────────────────────────────────
// StatefulWidget: render with external state

pub fn stateful_widget_render_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 10, height: 1))
  let buf = make_buf(10, 1)
  let w =
    widget.StatefulWidget(render: fn(b, a, s: String) {
      paragraph.render(b, a, paragraph.paragraph_new(s))
    })
  let result = widget.render_stateful(buf, area, w, "world")
  read_row(result, 0, 0, 5) |> should.equal("world")
}

pub fn freeze_bakes_state_into_stateless_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 8, height: 1))
  let buf = make_buf(8, 1)
  let sw =
    widget.StatefulWidget(render: fn(b, a, n: Int) {
      let s = case n {
        42 -> "life"
        _ -> "nope"
      }
      paragraph.render(b, a, paragraph.paragraph_new(s))
    })
  let w: widget.Widget = widget.freeze(sw, 42)
  let result = w(buf, area)
  read_row(result, 0, 0, 4) |> should.equal("life")
}

// ─────────────────────────────────────────────────────────────────
// AnimatedWidget: freeze_frame produces a stateless Widget

pub fn animated_widget_freeze_frame_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 6, height: 1))
  let buf = make_buf(6, 1)
  let aw: widget.AnimatedWidget = fn(b, a, frame) {
    let s = case frame {
      7 -> "seven"
      _ -> "other"
    }
    paragraph.render(b, a, paragraph.paragraph_new(s))
  }
  let w: widget.Widget = widget.freeze_frame(aw, 7)
  let result = w(buf, area)
  read_row(result, 0, 0, 5) |> should.equal("seven")
}

// ─────────────────────────────────────────────────────────────────
// Composition: layer

pub fn layer_draws_top_over_bottom_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 5, height: 1))
  let buf = make_buf(5, 1)
  let bottom: widget.Widget = fn(b, a) {
    paragraph.render(b, a, paragraph.paragraph_new("AAAAA"))
  }
  let top: widget.Widget = fn(b, _a) {
    let small =
      Rect(position: Position(x: 0, y: 0), size: Size(width: 3, height: 1))
    paragraph.render(b, small, paragraph.paragraph_new("BBB"))
  }
  let result = widget.layer(bottom, top)(buf, area)
  read_row(result, 0, 0, 3) |> should.equal("BBB")
  read_row(result, 0, 3, 2) |> should.equal("AA")
}

// ─────────────────────────────────────────────────────────────────
// Composition: stack

pub fn stack_renders_all_widgets_in_order_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 6, height: 1))
  let buf = make_buf(6, 1)
  let w1: widget.Widget = fn(b, a) {
    paragraph.render(b, a, paragraph.paragraph_new("AAABBB"))
  }
  let w2: widget.Widget = fn(b, _a) {
    let sub =
      Rect(position: Position(x: 3, y: 0), size: Size(width: 3, height: 1))
    paragraph.render(b, sub, paragraph.paragraph_new("CCC"))
  }
  let result = widget.stack([w1, w2])(buf, area)
  read_row(result, 0, 0, 6) |> should.equal("AAACCC")
}

// ─────────────────────────────────────────────────────────────────
// Composition: at pins to sub-area

pub fn at_pins_widget_to_subarea_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 10, height: 1))
  let buf = make_buf(10, 1)
  let sub =
    Rect(position: Position(x: 4, y: 0), size: Size(width: 4, height: 1))
  let w: widget.Widget = fn(b, a) {
    paragraph.render(b, a, paragraph.paragraph_new("XXXX"))
  }
  let result = widget.at(w, sub)(buf, area)
  read_row(result, 0, 4, 4) |> should.equal("XXXX")
  // Cells before the pinned area should be empty (space)
  let first = buffer.cell_symbol(buffer.get_cell(result, Position(x: 0, y: 0)))
  first |> should.equal(" ")
}

// ─────────────────────────────────────────────────────────────────
// empty() widget

pub fn empty_widget_is_noop_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 5, height: 1))
  let buf = make_buf(5, 1)
  let buf2 = paragraph.render(buf, area, paragraph.paragraph_new("HELLO"))
  let result = widget.empty()(buf2, area)
  read_row(result, 0, 0, 5) |> should.equal("HELLO")
}

// ─────────────────────────────────────────────────────────────────
// input: move_to_start / move_to_end / delete_to_end

pub fn input_move_to_start_test() {
  let s = ginput.state_from_string("hello")
  let s2 = ginput.move_to_start(s)
  s2.cursor |> should.equal(0)
  s2.value |> should.equal("hello")
}

pub fn input_move_to_end_test() {
  let s = ginput.state_from_string("hello")
  let s2 = ginput.move_to_start(s) |> ginput.move_to_end
  s2.cursor |> should.equal(5)
}

pub fn input_delete_to_end_test() {
  let s = ginput.state_from_string("hello")
  let s2 =
    ginput.move_to_start(s)
    |> ginput.move_cursor_right
    |> ginput.move_cursor_right
  let s3 = ginput.delete_to_end(s2)
  s3.value |> should.equal("he")
  s3.cursor |> should.equal(2)
}

pub fn input_insert_wide_char_advances_2_cells_test() {
  let w = ginput.input_new("")
  let s = ginput.state_new()
  let s1 = ginput.insert_char(w, s, "你")
  s1.cursor |> should.equal(2)
}

pub fn input_move_cursor_right_wide_skips_2_cells_test() {
  let s0 = ginput.InputState(value: "你ab", cursor: 0)
  let s1 = ginput.move_cursor_right(s0)
  s1.cursor |> should.equal(2)
}

pub fn input_move_cursor_left_wide_goes_to_0_test() {
  let s0 = ginput.InputState(value: "你ab", cursor: 2)
  let s1 = ginput.move_cursor_left(s0)
  s1.cursor |> should.equal(0)
}

// ─────────────────────────────────────────────────────────────────
// list: render_item_line overflow fix

pub fn list_row_width_is_exactly_area_width_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 10, height: 3))
  let buf = make_buf(10, 3)
  let l = glist.list_new(["alpha", "beta", "gamma"])
  let state = glist.state_new()
  let result = glist.render_stateful(buf, area, l, state)
  // Row 0 selected: prefix "▶ " (2 cells) + padded content = 10 cells total
  // Row 1 unselected: prefix "  " (2 cells) + padded content = 10 cells total
  let row0 = read_row(result, 0, 0, 10)
  text.cell_width(row0) |> should.equal(10)
  let row1 = read_row(result, 1, 0, 10)
  text.cell_width(row1) |> should.equal(10)
}

// ─────────────────────────────────────────────────────────────────
// text.wrap: explicit \n newlines

pub fn wrap_explicit_newline_test() {
  text.wrap("hello\nworld", 20) |> should.equal(["hello", "world"])
}

pub fn wrap_newline_then_word_wrap_test() {
  text.wrap("hello world\nfoo bar", 5)
  |> should.equal(["hello", "world", "foo", "bar"])
}

pub fn wrap_multiple_newlines_test() {
  text.wrap("a\nb\nc", 20) |> should.equal(["a", "b", "c"])
}

// ─────────────────────────────────────────────────────────────────
// style: Indexed(n>15) emits 256-color sequence

pub fn style_indexed_200_fg_test() {
  style.ansi_fg(style.Indexed(200)) |> should.equal("\u{001B}[38;5;200m")
}

pub fn style_indexed_128_bg_test() {
  style.ansi_bg(style.Indexed(128)) |> should.equal("\u{001B}[48;5;128m")
}

pub fn style_indexed_0_still_ansi_test() {
  style.ansi_fg(style.Indexed(0)) |> should.equal("\u{001B}[30m")
}

// ─────────────────────────────────────────────────────────────────
// block: with_bg_fill applies bg color to inner cells

pub fn block_bg_fill_sets_bg_color_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 5, height: 3))
  let buf = make_buf(5, 3)
  let blk =
    block.block_new()
    |> block.with_style(style.Default, style.Indexed(1))
    |> block.with_bg_fill
  let result = block.render(buf, area, blk)
  // No border on block_new(), so entire area is filled
  let cell = buffer.get_cell(result, Position(x: 2, y: 1))
  buffer.cell_bg(cell) |> should.equal(style.Indexed(1))
}

// ─────────────────────────────────────────────────────────────────
// popup: centered rect calculation

pub fn popup_rect_centered_test() {
  let screen =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 80, height: 24))
  let p = gpopup.popup_new(40, 10)
  let r = gpopup.popup_rect(screen, p)
  r.position.x |> should.equal(20)
  r.position.y |> should.equal(7)
  r.size.width |> should.equal(40)
  r.size.height |> should.equal(10)
}

pub fn popup_area_is_inside_border_test() {
  let screen =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 80, height: 24))
  let p = gpopup.popup_new(40, 10)
  let inner = gpopup.popup_area(screen, p)
  inner.position.x |> should.equal(21)
  inner.position.y |> should.equal(8)
  inner.size.width |> should.equal(38)
  inner.size.height |> should.equal(8)
}

pub fn popup_clamps_to_screen_test() {
  let screen =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 20, height: 10))
  let p = gpopup.popup_new(100, 100)
  let r = gpopup.popup_rect(screen, p)
  r.size.width |> should.equal(20)
  r.size.height |> should.equal(10)
}

// ─────────────────────────────────────────────────────────────────
// statusbar: renders sections at correct positions

pub fn statusbar_left_at_start_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 20, height: 1))
  let buf = make_buf(20, 1)
  let sb = gsbar.statusbar_new() |> gsbar.with_left([span.line_plain("LEFT")])
  let result = gsbar.render(buf, area, sb)
  read_row(result, 0, 0, 4) |> should.equal("LEFT")
}

pub fn statusbar_right_flush_right_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 20, height: 1))
  let buf = make_buf(20, 1)
  let sb = gsbar.statusbar_new() |> gsbar.with_right([span.line_plain("END")])
  let result = gsbar.render(buf, area, sb)
  read_row(result, 0, 17, 3) |> should.equal("END")
}

pub fn statusbar_plain_text_inherits_bar_background_test() {
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 12, height: 1))
  let buf = make_buf(12, 1)
  let sb =
    gsbar.statusbar_new()
    |> gsbar.with_left([span.line_plain("LEFT")])
    |> gsbar.with_style(style.Indexed(15), style.Indexed(4))
  let result = gsbar.render(buf, area, sb)
  buffer.cell_bg(buffer.get_cell(result, Position(x: 0, y: 0)))
  |> should.equal(style.Indexed(4))
  buffer.cell_bg(buffer.get_cell(result, Position(x: 8, y: 0)))
  |> should.equal(style.Indexed(4))
}
