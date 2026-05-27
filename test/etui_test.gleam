import etui/anim
import etui/buffer
import etui/color
import etui/cursor
import etui/focus
import etui/geometry.{
  Position, Rect, Size, area, bottom, contains, intersect, rect_new,
  resolve_sizes, right, split, union,
}
import etui/keymap
import etui/keys
import etui/span
import etui/style
import etui/text
import etui/undo
import etui/widgets/block
import etui/widgets/canvas as gcanvas_widget
import etui/widgets/chart as gchart_widget
import etui/widgets/dialog
import etui/widgets/form as gform_widget
import etui/widgets/gauge as ggauge_widget
import etui/widgets/gradient_bar as ggradient_widget
import etui/widgets/hbar as ghbar_widget
import etui/widgets/input as ginput_widget
import etui/widgets/line
import etui/widgets/list as glist_widget
import etui/widgets/marquee as gmarquee_widget
import etui/widgets/notification as gnotif_widget
import etui/widgets/paragraph
import etui/widgets/progress as gprogress_widget
import etui/widgets/scene as gscene_widget
import etui/widgets/scroll_view
import etui/widgets/sparkline as gspark_widget
import etui/widgets/spinner as gspinner_widget
import etui/widgets/table as gtable_widget
import etui/widgets/tabs as gtabs_widget
import etui/widgets/textarea
import etui/widgets/tree
import gleam/int
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

// ─────────────────────────────────────────────────────────────────
// Sacred 12 tests (must pass)

pub fn resolve_sizes_percentage_no_fill_test() {
  resolve_sizes(100, [
    geometry.Percentage(33),
    geometry.Percentage(33),
    geometry.Percentage(33),
  ])
  |> should.equal([33, 33, 33])
}

pub fn resolve_sizes_asymmetric_percentage_test() {
  resolve_sizes(100, [
    geometry.Percentage(33),
    geometry.Percentage(33),
    geometry.Percentage(34),
  ])
  |> should.equal([33, 33, 34])
}

pub fn resolve_sizes_percentage_with_fill_test() {
  resolve_sizes(100, [
    geometry.Percentage(33),
    geometry.Percentage(33),
    geometry.Percentage(33),
    geometry.Fill,
  ])
  |> should.equal([33, 33, 33, 1])
}

pub fn resolve_sizes_percentage_overflow_test() {
  resolve_sizes(100, [geometry.Percentage(60), geometry.Percentage(60)])
  |> should.equal([50, 50])
}

pub fn resolve_sizes_length_percentage_fill_test() {
  resolve_sizes(100, [
    geometry.Length(30),
    geometry.Percentage(50),
    geometry.Fill,
  ])
  |> should.equal([30, 50, 20])
}

pub fn resolve_sizes_length_overflow_percentage_test() {
  resolve_sizes(100, [geometry.Length(80), geometry.Percentage(50)])
  |> should.equal([80, 20])
}

pub fn resolve_sizes_consecutive_length_test() {
  resolve_sizes(100, [geometry.Length(60), geometry.Length(60)])
  |> should.equal([60, 40])
}

pub fn resolve_sizes_single_length_overflow_test() {
  resolve_sizes(100, [geometry.Length(120)])
  |> should.equal([100])
}

pub fn resolve_sizes_multiple_fill_test() {
  resolve_sizes(10, [geometry.Fill, geometry.Fill, geometry.Fill])
  |> should.equal([4, 3, 3])
}

pub fn resolve_sizes_fill_minimum_area_test() {
  resolve_sizes(1, [geometry.Fill, geometry.Fill])
  |> should.equal([1, 0])
}

pub fn resolve_sizes_zero_area_test() {
  resolve_sizes(0, [geometry.Fill, geometry.Length(10)])
  |> should.equal([0, 0])
}

pub fn resolve_sizes_empty_test() {
  resolve_sizes(100, [])
  |> should.equal([])
}

// ─────────────────────────────────────────────────────────────────
// Temporal stability tests

fn cumulative_sum(sizes: List(Int)) -> List(Int) {
  let #(_, acc) =
    list.fold(sizes, #(0, []), fn(state, size) {
      let #(cursor, sums) = state
      #(cursor + size, [cursor + size, ..sums])
    })
  list.reverse(acc)
}

pub fn stability_percentage_fill_on_range_test() {
  let r99 = resolve_sizes(99, [geometry.Percentage(50), geometry.Fill])
  let r100 = resolve_sizes(100, [geometry.Percentage(50), geometry.Fill])
  let r101 = resolve_sizes(101, [geometry.Percentage(50), geometry.Fill])
  let r102 = resolve_sizes(102, [geometry.Percentage(50), geometry.Fill])
  let r103 = resolve_sizes(103, [geometry.Percentage(50), geometry.Fill])

  let c99 = cumulative_sum(r99)
  let c100 = cumulative_sum(r100)
  let c101 = cumulative_sum(r101)
  let c102 = cumulative_sum(r102)
  let c103 = cumulative_sum(r103)

  case c99 {
    [b99, ..] ->
      case c100 {
        [b100, ..] ->
          case c101 {
            [b101, ..] ->
              case c102 {
                [b102, ..] ->
                  case c103 {
                    [b103, ..] -> {
                      b99 |> should.equal(49)
                      b100 |> should.equal(50)
                      b101 |> should.equal(50)
                      b102 |> should.equal(51)
                      b103 |> should.equal(51)
                    }
                    _ -> should.fail()
                  }
                _ -> should.fail()
              }
            _ -> should.fail()
          }
        _ -> should.fail()
      }
    _ -> should.fail()
  }
}

pub fn stability_fill_multiple_on_range_test() {
  resolve_sizes(2, [geometry.Fill, geometry.Fill])
  |> should.equal([1, 1])

  resolve_sizes(3, [geometry.Fill, geometry.Fill])
  |> should.equal([2, 1])

  resolve_sizes(4, [geometry.Fill, geometry.Fill])
  |> should.equal([2, 2])
}

pub fn stability_percentage_asymmetric_on_range_test() {
  let r100 =
    resolve_sizes(100, [
      geometry.Percentage(33),
      geometry.Percentage(33),
      geometry.Percentage(34),
    ])
  let r101 =
    resolve_sizes(101, [
      geometry.Percentage(33),
      geometry.Percentage(33),
      geometry.Percentage(34),
    ])

  r100 |> should.equal([33, 33, 34])
  r101 |> should.equal([33, 33, 35])
}

pub fn stability_length_fill_test() {
  resolve_sizes(10, [geometry.Length(10), geometry.Fill])
  |> should.equal([10, 0])

  resolve_sizes(11, [geometry.Length(10), geometry.Fill])
  |> should.equal([10, 1])

  resolve_sizes(15, [geometry.Length(10), geometry.Fill])
  |> should.equal([10, 5])
}

// ─────────────────────────────────────────────────────────────────
// Split tests

pub fn split_vertical_test() {
  let area = rect_new(0, 0, 100, 100)
  let chunks =
    split(geometry.Vertical, area, [
      geometry.Length(10),
      geometry.Percentage(20),
      geometry.Fill,
    ])

  chunks |> list.length |> should.equal(3)

  case chunks {
    [c0, c1, c2] -> {
      c0
      |> should.equal(Rect(Position(x: 0, y: 0), Size(width: 100, height: 10)))
      c1
      |> should.equal(Rect(Position(x: 0, y: 10), Size(width: 100, height: 20)))
      c2
      |> should.equal(Rect(Position(x: 0, y: 30), Size(width: 100, height: 70)))
    }
    other -> {
      other |> should.equal([])
    }
  }
}

pub fn split_horizontal_test() {
  let area = rect_new(0, 0, 100, 50)
  let chunks =
    split(geometry.Horizontal, area, [
      geometry.Percentage(50),
      geometry.Fill,
    ])

  chunks |> list.length |> should.equal(2)

  case chunks {
    [c0, c1] -> {
      c0
      |> should.equal(Rect(Position(x: 0, y: 0), Size(width: 50, height: 50)))
      c1
      |> should.equal(Rect(Position(x: 50, y: 0), Size(width: 50, height: 50)))
    }
    other -> {
      other |> should.equal([])
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Rect helpers

pub fn rect_new_clamps_negative_test() {
  rect_new(5, 10, -20, -30)
  |> should.equal(Rect(Position(x: 5, y: 10), Size(width: 0, height: 0)))
}

pub fn rect_right_test() {
  let r = rect_new(10, 20, 30, 40)
  right(r) |> should.equal(40)
}

pub fn rect_bottom_test() {
  let r = rect_new(10, 20, 30, 40)
  bottom(r) |> should.equal(60)
}

pub fn rect_area_test() {
  let r = rect_new(0, 0, 25, 10)
  area(r) |> should.equal(250)
}

pub fn rect_contains_test() {
  let r = rect_new(10, 10, 20, 20)

  contains(r, Position(x: 10, y: 10)) |> should.be_true()
  contains(r, Position(x: 15, y: 15)) |> should.be_true()
  contains(r, Position(x: 29, y: 29)) |> should.be_true()
  contains(r, Position(x: 30, y: 30)) |> should.be_false()
  contains(r, Position(x: 9, y: 15)) |> should.be_false()
}

pub fn rect_intersect_valid_test() {
  let a = rect_new(10, 10, 20, 20)
  let b = rect_new(15, 15, 20, 20)

  let result = intersect(a, b)
  result
  |> should.equal(Ok(Rect(Position(x: 15, y: 15), Size(width: 15, height: 15))))
}

pub fn rect_intersect_disjoint_test() {
  let a = rect_new(0, 0, 10, 10)
  let b = rect_new(20, 20, 10, 10)

  intersect(a, b) |> should.equal(Error(Nil))
}

pub fn rect_union_test() {
  let a = rect_new(0, 0, 10, 10)
  let b = rect_new(5, 5, 20, 20)

  let result = union(a, b)
  result
  |> should.equal(Rect(Position(x: 0, y: 0), Size(width: 25, height: 25)))
}

// ─────────────────────────────────────────────────────────────────
// Invariant checks

pub fn invariant_sizes_non_negative_test() {
  let result =
    resolve_sizes(100, [
      geometry.Length(30),
      geometry.Percentage(50),
      geometry.Fill,
      geometry.Length(20),
    ])

  list.all(result, fn(s) { s >= 0 })
  |> should.be_true()
}

pub fn invariant_sum_leq_total_test() {
  let total = 100
  let result =
    resolve_sizes(total, [
      geometry.Length(20),
      geometry.Percentage(30),
    ])

  let sum = list.fold(result, 0, fn(acc, s) { acc + s })

  sum
  |> int.min(total)
  |> should.equal(sum)
}

pub fn invariant_sum_eq_total_with_fill_test() {
  let total = 100
  let result =
    resolve_sizes(total, [
      geometry.Length(20),
      geometry.Percentage(30),
      geometry.Fill,
    ])

  list.fold(result, 0, fn(acc, s) { acc + s })
  |> should.equal(total)
}

// ─────────────────────────────────────────────────────────────────
// Text module tests (M2)

pub fn text_cell_width_ascii_test() {
  text.cell_width("hello") |> should.equal(5)
}

pub fn text_cell_width_empty_test() {
  text.cell_width("") |> should.equal(0)
}

pub fn text_cell_width_single_char_test() {
  text.cell_width("a") |> should.equal(1)
}

pub fn text_cell_width_space_test() {
  text.cell_width(" ") |> should.equal(1)
}

pub fn text_cell_width_mixed_test() {
  text.cell_width("Hello World!") |> should.equal(12)
}

pub fn text_truncate_basic_test() {
  // Greedy truncate: fits as much as possible + ellipsis
  text.truncate("hello world", 8, "…")
  |> should.equal("hello w…")
}

pub fn text_truncate_no_need_test() {
  text.truncate("hi", 10, "…")
  |> should.equal("hi")
}

pub fn text_truncate_zero_width_test() {
  text.truncate("hello", 0, "…")
  |> should.equal("")
}

pub fn text_wrap_single_line_test() {
  text.wrap("hello world", 20)
  |> should.equal(["hello world"])
}

pub fn text_wrap_two_lines_test() {
  text.wrap("hello world test", 8)
  |> should.equal(["hello", "world", "test"])
}

pub fn text_wrap_empty_test() {
  text.wrap("hello", 0)
  |> should.equal([])
}

pub fn text_pad_right_test() {
  text.pad_right("hi", 5)
  |> should.equal("hi   ")
}

pub fn text_pad_left_test() {
  text.pad_left("hi", 5)
  |> should.equal("   hi")
}

pub fn text_align_left_test() {
  text.align("hi", 5, text.Left)
  |> should.equal("hi   ")
}

pub fn text_align_right_test() {
  text.align("hi", 5, text.Right)
  |> should.equal("   hi")
}

pub fn text_align_center_test() {
  text.align("hi", 5, text.Center)
  |> should.equal(" hi  ")
}

pub fn text_strip_ansi_basic_test() {
  let styled = "\u{001B}[1mhello\u{001B}[0m"
  text.strip_ansi(styled)
  |> should.equal("hello")
}

pub fn text_strip_ansi_no_codes_test() {
  text.strip_ansi("plain")
  |> should.equal("plain")
}

pub fn text_strip_ansi_color_test() {
  let colored = "\u{001B}[32mgreen\u{001B}[0m"
  text.strip_ansi(colored)
  |> should.equal("green")
}

// ─────────────────────────────────────────────────────────────────
// Block widget tests

pub fn block_new_test() {
  let b = block.block_new()
  b.border |> should.equal(block.None)
  b.title |> should.equal("")
  b.padding_top |> should.equal(0)
}

pub fn block_with_border_test() {
  let b = block.block_new() |> block.with_border(block.Single)
  b.border |> should.equal(block.Single)
}

pub fn block_with_title_test() {
  let b = block.block_new() |> block.with_title("Test", block.Top)
  b.title |> should.equal("Test")
  b.title_position |> should.equal(block.Top)
}

pub fn block_with_padding_test() {
  let b = block.block_new() |> block.with_padding(1, 2, 3, 4)
  b.padding_top |> should.equal(1)
  b.padding_bottom |> should.equal(2)
  b.padding_left |> should.equal(3)
  b.padding_right |> should.equal(4)
}

pub fn block_render_no_border_test() {
  let area = rect_new(0, 0, 10, 10)
  let buf = buffer.buffer_new(area)
  let b = block.block_new()

  let result = block.render(buf, area, b)
  result |> buffer.area |> should.equal(area)
}

pub fn block_render_bordered_test() {
  let area = rect_new(0, 0, 10, 10)
  let buf = buffer.buffer_new(area)
  let b = block.block_new() |> block.with_border(block.Single)

  let result = block.render(buf, area, b)
  result |> buffer.area |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// Paragraph widget tests

pub fn paragraph_new_test() {
  let p = paragraph.paragraph_new("hello")
  p.text |> should.equal("hello")
}

pub fn paragraph_with_alignment_test() {
  let p =
    paragraph.paragraph_new("hello")
    |> paragraph.with_alignment(text.Left)
  p.alignment |> should.equal(text.Left)
}

pub fn paragraph_render_single_line_test() {
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let p = paragraph.paragraph_new("hello world")

  let result = paragraph.render(buf, area, p)
  result |> buffer.area |> should.equal(area)
}

pub fn paragraph_render_wrapped_test() {
  let area = rect_new(0, 0, 5, 5)
  let buf = buffer.buffer_new(area)
  let p = paragraph.paragraph_new("hello world test")

  let result = paragraph.render(buf, area, p)
  result |> buffer.area |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// Line widget tests

pub fn line_new_test() {
  let l = line.line_new()
  l.style |> should.equal(line.Solid)
  l.fg |> should.equal(style.Default)
}

pub fn line_with_color_test() {
  let l =
    line.line_new()
    |> line.with_color(style.Indexed(1))
  l.fg |> should.equal(style.Indexed(1))
}

pub fn line_render_horizontal_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let l = line.line_new()

  let result = line.render_horizontal(buf, area, l)
  result |> buffer.area |> should.equal(area)
}

pub fn line_render_vertical_test() {
  let area = rect_new(0, 0, 1, 10)
  let buf = buffer.buffer_new(area)
  let l = line.line_new()

  let result = line.render_vertical(buf, area, l)
  result |> buffer.area |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// List widget tests

pub fn list_new_test() {
  let items = ["Item 1", "Item 2", "Item 3"]
  let l = glist_widget.list_new(items)
  l.fg |> should.equal(style.Default)
}

pub fn list_state_new_test() {
  let state = glist_widget.state_new()
  state.selected |> should.equal(0)
  state.offset |> should.equal(0)
}

pub fn list_select_test() {
  let state = glist_widget.state_new() |> glist_widget.select(2)
  state.selected |> should.equal(2)
}

pub fn list_select_next_test() {
  let state = glist_widget.state_new() |> glist_widget.select_next(5)
  state.selected |> should.equal(1)
}

pub fn list_select_prev_clamps_test() {
  let state = glist_widget.state_new() |> glist_widget.select_prev()
  state.selected |> should.equal(0)
}

pub fn list_with_colors_test() {
  let items = ["Item 1", "Item 2"]
  let l =
    glist_widget.list_new(items)
    |> glist_widget.with_colors(style.Indexed(2), style.Indexed(3))
  l.fg |> should.equal(style.Indexed(2))
  l.bg |> should.equal(style.Indexed(3))
}

pub fn list_render_test() {
  let items = ["Item 1", "Item 2", "Item 3"]
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let l = glist_widget.list_new(items)

  let result = glist_widget.render(buf, area, l)
  result |> buffer.area |> should.equal(area)
}

pub fn list_render_stateful_test() {
  let items = ["Item 1", "Item 2", "Item 3"]
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let l = glist_widget.list_new(items)
  let state = glist_widget.state_new() |> glist_widget.select(1)

  let result = glist_widget.render_stateful(buf, area, l, state)
  result |> buffer.area |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// Table widget tests

pub fn table_new_test() {
  let rows = [["Name", "Age"], ["Alice", "30"], ["Bob", "25"]]
  let t = gtable_widget.table_new(rows)
  t.fg |> should.equal(style.Default)
}

pub fn table_state_new_test() {
  let state = gtable_widget.state_new()
  state.selected_row |> should.equal(0)
  state.offset |> should.equal(0)
}

pub fn table_select_row_test() {
  let state = gtable_widget.state_new() |> gtable_widget.select_row(2)
  state.selected_row |> should.equal(2)
}

pub fn table_with_col_widths_test() {
  let rows = [["X", "Y"]]
  let t =
    gtable_widget.table_new(rows)
    |> gtable_widget.with_col_widths([15, 20])
  t.col_widths |> should.equal([15, 20])
}

pub fn table_with_header_test() {
  let rows = [["Col1", "Col2"]]
  let t =
    gtable_widget.table_new(rows)
    |> gtable_widget.with_header(True)
  t.show_header |> should.equal(True)
}

pub fn table_render_test() {
  let rows = [["A", "B"], ["C", "D"], ["E", "F"]]
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let t = gtable_widget.table_new(rows)

  let result = gtable_widget.render(buf, area, t)
  result |> buffer.area |> should.equal(area)
}

pub fn table_render_stateful_test() {
  let rows = [["A", "B"], ["C", "D"], ["E", "F"]]
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let t = gtable_widget.table_new(rows)
  let state = gtable_widget.state_new() |> gtable_widget.select_row(1)

  let result = gtable_widget.render_stateful(buf, area, t, state)
  result |> buffer.area |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// Input widget tests

pub fn input_new_test() {
  let w = ginput_widget.input_new("Enter text")
  w.placeholder |> should.equal("Enter text")
  w.max_length |> should.equal(256)
}

pub fn input_state_new_test() {
  let s = ginput_widget.state_new()
  s.value |> should.equal("")
  s.cursor |> should.equal(0)
}

pub fn input_state_from_string_test() {
  let s = ginput_widget.state_from_string("hello")
  s.value |> should.equal("hello")
  s.cursor |> should.equal(5)
}

pub fn input_insert_char_test() {
  let w = ginput_widget.input_new("")
  let s0 = ginput_widget.state_new()
  let s1 = ginput_widget.insert_char(w, s0, "a")
  let s2 = ginput_widget.insert_char(w, s1, "b")
  s2.value |> should.equal("ab")
  s2.cursor |> should.equal(2)
}

pub fn input_backspace_test() {
  let s =
    ginput_widget.state_from_string("hello")
    |> ginput_widget.backspace()
  s.value |> should.equal("hell")
  s.cursor |> should.equal(4)
}

pub fn input_move_cursor_test() {
  let s =
    ginput_widget.state_from_string("test")
    |> ginput_widget.move_cursor_left()
    |> ginput_widget.move_cursor_left()
  s.cursor |> should.equal(2)

  let s2 = s |> ginput_widget.move_cursor_right()
  s2.cursor |> should.equal(3)
}

pub fn input_clear_test() {
  let s =
    ginput_widget.state_from_string("content")
    |> ginput_widget.clear_state()
  s.value |> should.equal("")
  s.cursor |> should.equal(0)
}

pub fn input_render_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)
  let w = ginput_widget.input_new("default")
  let s = ginput_widget.state_new()

  let result = ginput_widget.render(buf, area, w, s)
  result |> buffer.area |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// Gauge widget tests

pub fn gauge_new_test() {
  let g = ggauge_widget.gauge_new(75)
  g.percent |> should.equal(75)
  g.label |> should.equal("")
}

pub fn gauge_clamps_percent_test() {
  ggauge_widget.gauge_new(150).percent |> should.equal(100)
  ggauge_widget.gauge_new(-10).percent |> should.equal(0)
}

pub fn gauge_with_label_test() {
  let g = ggauge_widget.gauge_new(50) |> ggauge_widget.with_label("50%")
  g.label |> should.equal("50%")
}

pub fn gauge_render_empty_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let g = ggauge_widget.gauge_new(0)
  let result = ggauge_widget.render(buf, area, g)
  result |> buffer.area |> should.equal(area)
}

pub fn gauge_render_full_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let g = ggauge_widget.gauge_new(100)
  let result = ggauge_widget.render(buf, area, g)
  result |> buffer.area |> should.equal(area)
}

pub fn gauge_render_partial_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let g = ggauge_widget.gauge_new(50)
  let result = ggauge_widget.render(buf, area, g)
  result |> buffer.area |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// Scroll tests

pub fn list_scroll_into_view_down_test() {
  // selected=5, offset=0, height=3 → offset should become 3
  let state = glist_widget.ListState(selected: 5, offset: 0)
  let items = ["a", "b", "c", "d", "e", "f", "g"]
  let area = rect_new(0, 0, 20, 3)
  let buf = buffer.buffer_new(area)
  let l = glist_widget.list_new(items)
  // render_stateful auto-adjusts offset; result must not crash
  let result = glist_widget.render_stateful(buf, area, l, state)
  result |> buffer.area |> should.equal(area)
}

pub fn list_scroll_into_view_up_test() {
  // selected=0 but offset=3 → should scroll back up
  let state = glist_widget.ListState(selected: 0, offset: 3)
  let items = ["a", "b", "c", "d", "e"]
  let area = rect_new(0, 0, 20, 3)
  let buf = buffer.buffer_new(area)
  let l = glist_widget.list_new(items)
  let result = glist_widget.render_stateful(buf, area, l, state)
  result |> buffer.area |> should.equal(area)
}

pub fn list_highlight_style_test() {
  let items = ["Item 1", "Item 2"]
  let s =
    style.Style(fg: style.Default, bg: style.Default, modifier: style.bold())
  let l =
    glist_widget.list_new(items)
    |> glist_widget.with_highlight_style(s)
  l.highlight_style.modifier |> should.equal(style.bold())
}

pub fn table_highlight_style_test() {
  let rows = [["A", "B"], ["C", "D"]]
  let s =
    style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.add(style.bold(), style.reverse()),
    )
  let t =
    gtable_widget.table_new(rows)
    |> gtable_widget.with_highlight_style(s)
  t.highlight_style.modifier
  |> should.equal(style.add(style.bold(), style.reverse()))
}

// ─────────────────────────────────────────────────────────────────
// Style type tests

pub fn style_default_test() {
  let s = style.default_style()
  s.fg |> should.equal(style.Default)
  s.bg |> should.equal(style.Default)
  s.modifier |> should.equal(style.none())
}

pub fn style_with_fg_test() {
  let s = style.default_style() |> style.with_fg(style.Indexed(1))
  s.fg |> should.equal(style.Indexed(1))
}

pub fn style_with_modifier_test() {
  let s = style.default_style() |> style.with_modifier(style.bold())
  s.modifier |> should.equal(style.bold())
}

pub fn style_bold_test() {
  style.bold_style().modifier |> should.equal(style.bold())
}

pub fn style_reversed_test() {
  style.reversed().modifier |> should.equal(style.reverse())
}

pub fn style_patch_test() {
  let base =
    style.Style(
      fg: style.Indexed(1),
      bg: style.Indexed(2),
      modifier: style.bold(),
    )
  let over =
    style.Style(fg: style.Default, bg: style.Indexed(3), modifier: style.none())
  let result = style.patch(base, over)
  result.fg |> should.equal(style.Indexed(1))
  result.bg |> should.equal(style.Indexed(3))
  result.modifier |> should.equal(style.bold())
}

// ─────────────────────────────────────────────────────────────────
// Anim easing + sequence tests

pub fn anim_interpolate_linear_test() {
  anim.interpolate(0, 100, 5, 10, anim.Linear) |> should.equal(50)
}

pub fn anim_interpolate_ease_out_test() {
  anim.interpolate(0, 100, 10, 10, anim.EaseOut) |> should.equal(100)
  anim.interpolate(0, 100, 0, 10, anim.EaseOut) |> should.equal(0)
}

pub fn anim_interpolate_ease_in_out_test() {
  anim.interpolate(0, 100, 0, 10, anim.EaseInOut) |> should.equal(0)
  anim.interpolate(0, 100, 10, 10, anim.EaseInOut) |> should.equal(100)
}

pub fn anim_ease_in_out_midpoint_test() {
  let mid = anim.ease_in_out(0, 100, 5, 10)
  mid |> should.equal(50)
}

pub fn anim_sequence_linear_test() {
  let kfs = [anim.Keyframe(0, 0), anim.Keyframe(10, 100), anim.Keyframe(20, 50)]
  anim.sequence(kfs, 0, anim.Linear) |> should.equal(0)
  anim.sequence(kfs, 5, anim.Linear) |> should.equal(50)
  anim.sequence(kfs, 10, anim.Linear) |> should.equal(100)
  anim.sequence(kfs, 20, anim.Linear) |> should.equal(50)
  anim.sequence(kfs, 99, anim.Linear) |> should.equal(50)
}

pub fn anim_sequence_empty_test() {
  anim.sequence([], 5, anim.Linear) |> should.equal(0)
}

pub fn anim_sequence_single_test() {
  anim.sequence([anim.Keyframe(0, 42)], 99, anim.Linear) |> should.equal(42)
}

// ─────────────────────────────────────────────────────────────────
// Spinner custom style test

pub fn spinner_custom_frames_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)
  let s =
    gspinner_widget.spinner_new()
    |> gspinner_widget.with_style(gspinner_widget.Custom(["A", "B", "C"]))
  let result = gspinner_widget.render(buf, area, s, 0)
  result |> buffer.area |> should.equal(area)
}

pub fn spinner_custom_cycles_test() {
  let area = rect_new(0, 0, 1, 1)
  let buf = buffer.buffer_new(area)
  let s =
    gspinner_widget.spinner_new()
    |> gspinner_widget.with_style(gspinner_widget.Custom(["X", "Y"]))
  [0, 1, 2, 3]
  |> list.each(fn(f) {
    let _ = gspinner_widget.render(buf, area, s, f)
    Nil
  })
}

// ─────────────────────────────────────────────────────────────────
// Anim tests

pub fn anim_new_test() {
  let a = anim.anim_new()
  a.frame |> should.equal(0)
}

pub fn anim_tick_test() {
  let a = anim.anim_new() |> anim.tick() |> anim.tick() |> anim.tick()
  a.frame |> should.equal(3)
}

pub fn anim_reset_test() {
  let a = anim.anim_new() |> anim.tick() |> anim.tick() |> anim.reset()
  a.frame |> should.equal(0)
}

pub fn anim_is_done_test() {
  anim.is_done(anim.AnimState(frame: 10), 10) |> should.be_true()
  anim.is_done(anim.AnimState(frame: 5), 10) |> should.be_false()
}

pub fn anim_cycle_test() {
  anim.cycle(0, 4) |> should.equal(0)
  anim.cycle(3, 4) |> should.equal(3)
  anim.cycle(4, 4) |> should.equal(0)
  anim.cycle(7, 4) |> should.equal(3)
}

pub fn anim_lerp_test() {
  anim.lerp(0, 100, 0, 10) |> should.equal(0)
  anim.lerp(0, 100, 5, 10) |> should.equal(50)
  anim.lerp(0, 100, 10, 10) |> should.equal(100)
  anim.lerp(0, 100, 99, 10) |> should.equal(100)
}

pub fn anim_lerp_zero_duration_test() {
  anim.lerp(0, 100, 5, 0) |> should.equal(100)
}

pub fn anim_ease_out_ends_at_target_test() {
  anim.ease_out(0, 100, 10, 10) |> should.equal(100)
  anim.ease_out(0, 100, 0, 10) |> should.equal(0)
}

pub fn anim_ease_in_ends_at_target_test() {
  anim.ease_in(0, 100, 10, 10) |> should.equal(100)
  anim.ease_in(0, 100, 0, 10) |> should.equal(0)
}

pub fn anim_oscillate_test() {
  anim.oscillate(0, 10, 0, 20) |> should.equal(0)
  anim.oscillate(0, 10, 10, 20) |> should.equal(10)
}

// ─────────────────────────────────────────────────────────────────
// Spinner widget tests

pub fn spinner_new_test() {
  let s = gspinner_widget.spinner_new()
  s.label |> should.equal("")
  s.fg |> should.equal(style.Default)
}

pub fn spinner_with_label_test() {
  let s = gspinner_widget.spinner_new() |> gspinner_widget.with_label("Loading")
  s.label |> should.equal("Loading")
}

pub fn spinner_render_dots_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)
  let s = gspinner_widget.spinner_new()
  let result = gspinner_widget.render(buf, area, s, 0)
  result |> buffer.area |> should.equal(area)
}

pub fn spinner_render_all_styles_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)

  [
    gspinner_widget.Dots,
    gspinner_widget.Line,
    gspinner_widget.Circle,
    gspinner_widget.Bounce,
  ]
  |> list.each(fn(sty) {
    let s = gspinner_widget.spinner_new() |> gspinner_widget.with_style(sty)
    let result = gspinner_widget.render(buf, area, s, 42)
    result |> buffer.area |> should.equal(area)
  })
}

pub fn spinner_cycles_frames_test() {
  let area = rect_new(0, 0, 1, 1)
  let buf = buffer.buffer_new(area)
  let s =
    gspinner_widget.spinner_new()
    |> gspinner_widget.with_style(gspinner_widget.Line)
  [0, 1, 2, 3, 4, 5, 6, 7]
  |> list.each(fn(f) {
    let _ = gspinner_widget.render(buf, area, s, f)
    Nil
  })
}

// ─────────────────────────────────────────────────────────────────
// Anim blink tests

pub fn anim_blink_on_test() {
  anim.blink(0, 10) |> should.be_true()
  anim.blink(4, 10) |> should.be_true()
}

pub fn anim_blink_off_test() {
  anim.blink(5, 10) |> should.be_false()
  anim.blink(9, 10) |> should.be_false()
}

pub fn anim_blink_zero_period_always_on_test() {
  anim.blink(0, 0) |> should.be_true()
  anim.blink(999, 0) |> should.be_true()
}

// ─────────────────────────────────────────────────────────────────
// Cursor tests

pub fn cursor_set_shape_block_test() {
  cursor.set_shape(cursor.Block) |> should.equal("\u{001B}[2 q")
}

pub fn cursor_set_shape_bar_blink_test() {
  cursor.set_shape(cursor.BarBlink) |> should.equal("\u{001B}[5 q")
}

pub fn cursor_show_hide_test() {
  cursor.show() |> should.equal("\u{001B}[?25h")
  cursor.hide() |> should.equal("\u{001B}[?25l")
}

pub fn cursor_move_to_test() {
  cursor.move_to(1, 1) |> should.equal("\u{001B}[1;1H")
  cursor.move_to(10, 42) |> should.equal("\u{001B}[10;42H")
}

// ─────────────────────────────────────────────────────────────────
// Progress widget tests

pub fn progress_new_test() {
  let p = gprogress_widget.progress_new(75)
  p.label |> should.equal("")
}

pub fn progress_clamps_percent_test() {
  let p = gprogress_widget.progress_new(150)
  case p.mode {
    gprogress_widget.Determinate(pct) -> pct |> should.equal(100)
    _ -> should.fail()
  }
}

pub fn progress_indeterminate_mode_test() {
  let p = gprogress_widget.progress_indeterminate()
  case p.mode {
    gprogress_widget.Indeterminate -> Nil
    _ -> should.fail()
  }
}

pub fn progress_render_determinate_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)
  let p = gprogress_widget.progress_new(50)
  let result = gprogress_widget.render(buf, area, p, 0)
  result |> buffer.area |> should.equal(area)
}

pub fn progress_render_indeterminate_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)
  let p = gprogress_widget.progress_indeterminate()
  [0, 10, 20, 30]
  |> list.each(fn(f) {
    let result = gprogress_widget.render(buf, area, p, f)
    result |> buffer.area |> should.equal(area)
  })
}

pub fn progress_render_zero_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  gprogress_widget.render(buf, area, gprogress_widget.progress_new(0), 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn progress_render_full_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  gprogress_widget.render(buf, area, gprogress_widget.progress_new(100), 0)
  |> buffer.area
  |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// Blinking list/table tests

pub fn list_render_animated_steady_test() {
  let items = ["a", "b", "c"]
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let l = glist_widget.list_new(items)
  let state = glist_widget.state_new()
  // blink_period=0 → always visible
  let result = glist_widget.render_animated(buf, area, l, state, 42)
  result |> buffer.area |> should.equal(area)
}

pub fn list_render_animated_blink_test() {
  let items = ["a", "b", "c"]
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let l = glist_widget.list_new(items) |> glist_widget.with_blink(10)
  let state = glist_widget.state_new()
  // frame=0 → on, frame=5 → off — both must render without crash
  let r1 = glist_widget.render_animated(buf, area, l, state, 0)
  let r2 = glist_widget.render_animated(buf, area, l, state, 5)
  r1 |> buffer.area |> should.equal(area)
  r2 |> buffer.area |> should.equal(area)
}

pub fn table_render_animated_blink_test() {
  let rows = [["A", "B"], ["C", "D"]]
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let t = gtable_widget.table_new(rows) |> gtable_widget.with_blink(10)
  let state = gtable_widget.state_new()
  let r1 = gtable_widget.render_animated(buf, area, t, state, 0)
  let r2 = gtable_widget.render_animated(buf, area, t, state, 5)
  r1 |> buffer.area |> should.equal(area)
  r2 |> buffer.area |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// color.gleam tests

pub fn lerp_rgb_full_test() {
  color.lerp_rgb(style.Rgb(0, 0, 0), style.Rgb(100, 200, 50), 1, 1)
  |> should.equal(style.Rgb(100, 200, 50))
}

pub fn lerp_rgb_zero_test() {
  color.lerp_rgb(style.Rgb(0, 0, 0), style.Rgb(100, 200, 50), 0, 1)
  |> should.equal(style.Rgb(0, 0, 0))
}

pub fn lerp_rgb_midpoint_test() {
  color.lerp_rgb(style.Rgb(0, 0, 0), style.Rgb(200, 100, 50), 1, 2)
  |> should.equal(style.Rgb(100, 50, 25))
}

pub fn lerp_rgb_non_rgb_low_test() {
  color.lerp_rgb(style.Default, style.Indexed(1), 0, 10)
  |> should.equal(style.Default)
}

pub fn lerp_rgb_non_rgb_high_test() {
  color.lerp_rgb(style.Default, style.Indexed(1), 5, 10)
  |> should.equal(style.Indexed(1))
}

pub fn hue_to_rgb_red_test() {
  color.hue_to_rgb(0)
  |> should.equal(style.Rgb(255, 0, 0))
}

pub fn hue_to_rgb_green_test() {
  color.hue_to_rgb(120)
  |> should.equal(style.Rgb(0, 255, 0))
}

pub fn hue_to_rgb_blue_test() {
  color.hue_to_rgb(240)
  |> should.equal(style.Rgb(0, 0, 255))
}

pub fn hue_to_rgb_wrap_test() {
  color.hue_to_rgb(360)
  |> should.equal(color.hue_to_rgb(0))
}

pub fn hue_to_rgb_negative_test() {
  let c = color.hue_to_rgb(-1)
  c |> should.not_equal(style.Default)
}

pub fn rainbow_returns_rgb_test() {
  let c = color.rainbow(0, 60)
  case c {
    style.Rgb(_, _, _) -> True
    _ -> False
  }
  |> should.equal(True)
}

pub fn rainbow_period_zero_test() {
  let c = color.rainbow(5, 0)
  c |> should.not_equal(style.Default)
}

pub fn gradient_empty_test() {
  color.gradient([], 0, 100)
  |> should.equal(style.Default)
}

pub fn gradient_single_test() {
  color.gradient([style.Rgb(255, 0, 0)], 50, 100)
  |> should.equal(style.Rgb(255, 0, 0))
}

pub fn gradient_two_stops_start_test() {
  color.gradient([style.Rgb(0, 0, 0), style.Rgb(100, 0, 0)], 0, 100)
  |> should.equal(style.Rgb(0, 0, 0))
}

pub fn gradient_two_stops_end_test() {
  color.gradient([style.Rgb(0, 0, 0), style.Rgb(100, 0, 0)], 100, 100)
  |> should.equal(style.Rgb(100, 0, 0))
}

pub fn pulse_non_rgb_passthrough_test() {
  color.pulse(style.Default, 0, 30)
  |> should.equal(style.Default)
}

pub fn pulse_rgb_returns_rgb_test() {
  let c = color.pulse(style.Rgb(255, 255, 255), 0, 30)
  case c {
    style.Rgb(_, _, _) -> True
    _ -> False
  }
  |> should.equal(True)
}

pub fn scale_full_test() {
  color.scale(style.Rgb(200, 100, 50), 255)
  |> should.equal(style.Rgb(200, 100, 50))
}

pub fn scale_half_test() {
  color.scale(style.Rgb(200, 100, 50), 128)
  |> should.equal(style.Rgb(100, 50, 25))
}

pub fn scale_zero_test() {
  color.scale(style.Rgb(200, 100, 50), 0)
  |> should.equal(style.Rgb(0, 0, 0))
}

pub fn scale_non_rgb_passthrough_test() {
  color.scale(style.Indexed(3), 128)
  |> should.equal(style.Indexed(3))
}

// ─────────────────────────────────────────────────────────────────
// gradient_bar.gleam tests

pub fn gradient_bar_render_area_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)
  let stops = [style.Rgb(0, 0, 255), style.Rgb(255, 0, 0)]
  let g = ggradient_widget.gradient_bar_new(stops)
  ggradient_widget.render(buf, area, g, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn gradient_bar_zero_area_test() {
  let area = rect_new(0, 0, 0, 0)
  let buf = buffer.buffer_new(area)
  let g = ggradient_widget.rainbow_bar()
  ggradient_widget.render(buf, area, g, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn rainbow_bar_render_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let g = ggradient_widget.rainbow_bar()
  ggradient_widget.render(buf, area, g, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn animated_rainbow_bar_render_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let g = ggradient_widget.animated_rainbow_bar()
  let r1 = ggradient_widget.render(buf, area, g, 0)
  let r2 = ggradient_widget.render(buf, area, g, 30)
  r1 |> buffer.area |> should.equal(area)
  r2 |> buffer.area |> should.equal(area)
}

pub fn gradient_progress_partial_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)
  let stops = [style.Rgb(0, 255, 0), style.Rgb(255, 0, 0)]
  let g = ggradient_widget.gradient_progress_new(stops, 50)
  ggradient_widget.render(buf, area, g, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn gradient_progress_zero_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)
  let stops = [style.Rgb(0, 255, 0), style.Rgb(255, 0, 0)]
  let g = ggradient_widget.gradient_progress_new(stops, 0)
  ggradient_widget.render(buf, area, g, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn gradient_bar_with_percent_clamp_test() {
  let g = ggradient_widget.rainbow_bar() |> ggradient_widget.with_percent(150)
  g.percent |> should.equal(100)
}

pub fn pulse_bar_render_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let g = ggradient_widget.pulse_bar(style.Rgb(0, 180, 255))
  let r1 = ggradient_widget.render(buf, area, g, 0)
  let r2 = ggradient_widget.render(buf, area, g, 15)
  r1 |> buffer.area |> should.equal(area)
  r2 |> buffer.area |> should.equal(area)
}

pub fn animated_gradient_render_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let stops = [style.Rgb(0, 0, 255), style.Rgb(0, 255, 0), style.Rgb(255, 0, 0)]
  let g = ggradient_widget.animated_gradient_bar_new(stops)
  let r1 = ggradient_widget.render(buf, area, g, 0)
  let r2 = ggradient_widget.render(buf, area, g, 60)
  r1 |> buffer.area |> should.equal(area)
  r2 |> buffer.area |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// sparkline tests

pub fn sparkline_render_area_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let s = gspark_widget.sparkline_new([10, 20, 50, 80, 100, 40, 60, 30, 70, 90])
  gspark_widget.render(buf, area, s, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn sparkline_zero_area_test() {
  let area = rect_new(0, 0, 0, 0)
  let buf = buffer.buffer_new(area)
  let s = gspark_widget.sparkline_new([10, 50, 100])
  gspark_widget.render(buf, area, s, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn sparkline_empty_data_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let s = gspark_widget.sparkline_new([])
  gspark_widget.render(buf, area, s, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn sparkline_rainbow_fill_test() {
  let area = rect_new(0, 0, 8, 1)
  let buf = buffer.buffer_new(area)
  let s =
    gspark_widget.sparkline_new([10, 30, 60, 100, 80, 50, 20, 40])
    |> gspark_widget.with_fill(gspark_widget.SparkRainbow)
  gspark_widget.render(buf, area, s, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn sparkline_animated_rainbow_test() {
  let area = rect_new(0, 0, 8, 1)
  let buf = buffer.buffer_new(area)
  let s =
    gspark_widget.sparkline_new([10, 30, 60, 100, 80, 50, 20, 40])
    |> gspark_widget.with_fill(gspark_widget.SparkAnimatedRainbow)
  let r1 = gspark_widget.render(buf, area, s, 0)
  let r2 = gspark_widget.render(buf, area, s, 30)
  r1 |> buffer.area |> should.equal(area)
  r2 |> buffer.area |> should.equal(area)
}

pub fn sparkline_solid_fill_test() {
  let area = rect_new(0, 0, 5, 1)
  let buf = buffer.buffer_new(area)
  let s =
    gspark_widget.sparkline_new([0, 25, 50, 75, 100])
    |> gspark_widget.with_fill(gspark_widget.SparkSolid(style.Rgb(0, 255, 0)))
  gspark_widget.render(buf, area, s, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn sparkline_animated_gradient_test() {
  let area = rect_new(0, 0, 8, 1)
  let buf = buffer.buffer_new(area)
  let s =
    gspark_widget.sparkline_new([10, 30, 60, 100, 80, 50, 20, 40])
    |> gspark_widget.with_fill(
      gspark_widget.SparkAnimated([style.Rgb(0, 0, 255), style.Rgb(255, 0, 0)]),
    )
  let r1 = gspark_widget.render(buf, area, s, 0)
  let r2 = gspark_widget.render(buf, area, s, 60)
  r1 |> buffer.area |> should.equal(area)
  r2 |> buffer.area |> should.equal(area)
}

pub fn sparkline_with_max_test() {
  let area = rect_new(0, 0, 5, 1)
  let buf = buffer.buffer_new(area)
  let s =
    gspark_widget.sparkline_new([200, 150, 100, 50, 0])
    |> gspark_widget.with_max(200)
  gspark_widget.render(buf, area, s, 0)
  |> buffer.area
  |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// marquee tests

pub fn marquee_render_area_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)
  let m = gmarquee_widget.marquee_new("Hello world")
  gmarquee_widget.render(buf, area, m, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn marquee_zero_area_test() {
  let area = rect_new(0, 0, 0, 0)
  let buf = buffer.buffer_new(area)
  let m = gmarquee_widget.marquee_new("Hello world")
  gmarquee_widget.render(buf, area, m, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn marquee_scrolls_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let m =
    gmarquee_widget.marquee_new("ABCDEFGHIJKLMNOP")
    |> gmarquee_widget.with_speed(1)
  let r1 = gmarquee_widget.render(buf, area, m, 0)
  let r2 = gmarquee_widget.render(buf, area, m, 5)
  r1 |> buffer.area |> should.equal(area)
  r2 |> buffer.area |> should.equal(area)
}

pub fn marquee_empty_text_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let m = gmarquee_widget.marquee_new("")
  gmarquee_widget.render(buf, area, m, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn marquee_speed_clamp_test() {
  let m = gmarquee_widget.marquee_new("test") |> gmarquee_widget.with_speed(0)
  m.speed |> should.equal(1)
}

pub fn marquee_separator_test() {
  let area = rect_new(0, 0, 30, 1)
  let buf = buffer.buffer_new(area)
  let m =
    gmarquee_widget.marquee_new("Hi")
    |> gmarquee_widget.with_separator(" -- ")
  gmarquee_widget.render(buf, area, m, 0)
  |> buffer.area
  |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// tabs tests

pub fn tabs_render_area_test() {
  let area = rect_new(0, 0, 40, 1)
  let buf = buffer.buffer_new(area)
  let t = gtabs_widget.tabs_new(["Home", "Settings", "About"])
  gtabs_widget.render(buf, area, t)
  |> buffer.area
  |> should.equal(area)
}

pub fn tabs_zero_area_test() {
  let area = rect_new(0, 0, 0, 0)
  let buf = buffer.buffer_new(area)
  let t = gtabs_widget.tabs_new(["A", "B"])
  gtabs_widget.render(buf, area, t)
  |> buffer.area
  |> should.equal(area)
}

pub fn tabs_active_index_test() {
  let t = gtabs_widget.tabs_new(["A", "B", "C"]) |> gtabs_widget.with_active(2)
  t.active |> should.equal(2)
}

pub fn tabs_next_prev_test() {
  let t = gtabs_widget.tabs_new(["A", "B", "C"]) |> gtabs_widget.with_active(0)
  gtabs_widget.next_tab(t).active |> should.equal(1)
}

pub fn tabs_next_wraps_test() {
  let t = gtabs_widget.tabs_new(["A", "B", "C"]) |> gtabs_widget.with_active(2)
  gtabs_widget.next_tab(t).active |> should.equal(0)
}

pub fn tabs_prev_wraps_test() {
  let t = gtabs_widget.tabs_new(["A", "B", "C"]) |> gtabs_widget.with_active(0)
  gtabs_widget.prev_tab(t).active |> should.equal(2)
}

pub fn tabs_empty_labels_test() {
  let area = rect_new(0, 0, 20, 1)
  let buf = buffer.buffer_new(area)
  let t = gtabs_widget.tabs_new([])
  gtabs_widget.render(buf, area, t)
  |> buffer.area
  |> should.equal(area)
}

pub fn tabs_custom_divider_test() {
  let area = rect_new(0, 0, 30, 1)
  let buf = buffer.buffer_new(area)
  let t =
    gtabs_widget.tabs_new(["X", "Y"])
    |> gtabs_widget.with_divider(" | ")
    |> gtabs_widget.with_padding(2)
  gtabs_widget.render(buf, area, t)
  |> buffer.area
  |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// chart tests

pub fn chart_render_area_test() {
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let c = gchart_widget.chart_new([10, 50, 80, 30, 100])
  gchart_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn chart_zero_area_test() {
  let area = rect_new(0, 0, 0, 0)
  let buf = buffer.buffer_new(area)
  let c = gchart_widget.chart_new([10, 50, 80])
  gchart_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn chart_empty_data_test() {
  let area = rect_new(0, 0, 10, 5)
  let buf = buffer.buffer_new(area)
  let c = gchart_widget.chart_new([])
  gchart_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn chart_rainbow_fill_test() {
  let area = rect_new(0, 0, 15, 5)
  let buf = buffer.buffer_new(area)
  let c =
    gchart_widget.chart_new([20, 60, 100, 40, 80])
    |> gchart_widget.with_fill(gchart_widget.ChartRainbow)
  gchart_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn chart_animated_rainbow_test() {
  let area = rect_new(0, 0, 15, 5)
  let buf = buffer.buffer_new(area)
  let c =
    gchart_widget.chart_new([20, 60, 100, 40, 80])
    |> gchart_widget.with_fill(gchart_widget.ChartAnimatedRainbow)
  let r1 = gchart_widget.render(buf, area, c, 0)
  let r2 = gchart_widget.render(buf, area, c, 35)
  r1 |> buffer.area |> should.equal(area)
  r2 |> buffer.area |> should.equal(area)
}

pub fn chart_gradient_fill_test() {
  let area = rect_new(0, 0, 15, 5)
  let buf = buffer.buffer_new(area)
  let c =
    gchart_widget.chart_new([20, 60, 100, 40, 80])
    |> gchart_widget.with_fill(
      gchart_widget.ChartGradient([style.Rgb(0, 0, 255), style.Rgb(255, 0, 0)]),
    )
  gchart_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn chart_vertical_gradient_test() {
  let area = rect_new(0, 0, 15, 5)
  let buf = buffer.buffer_new(area)
  let c =
    gchart_widget.chart_new([20, 60, 100, 40, 80])
    |> gchart_widget.with_fill(
      gchart_widget.ChartVerticalGradient([
        style.Rgb(0, 255, 0),
        style.Rgb(255, 255, 0),
        style.Rgb(255, 0, 0),
      ]),
    )
  gchart_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn chart_solid_fill_test() {
  let area = rect_new(0, 0, 15, 5)
  let buf = buffer.buffer_new(area)
  let c =
    gchart_widget.chart_new([20, 60, 100])
    |> gchart_widget.with_fill(
      gchart_widget.ChartSolid([
        style.Rgb(255, 0, 0),
        style.Rgb(0, 255, 0),
        style.Rgb(0, 0, 255),
      ]),
    )
  gchart_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn chart_with_max_test() {
  let area = rect_new(0, 0, 15, 5)
  let buf = buffer.buffer_new(area)
  let c =
    gchart_widget.chart_new([200, 150, 100])
    |> gchart_widget.with_max(200)
    |> gchart_widget.with_bar_width(4)
    |> gchart_widget.with_gap(1)
  gchart_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// HBar widget tests

pub fn hbar_render_area_test() {
  let area = rect_new(0, 0, 30, 4)
  let buf = buffer.buffer_new(area)
  let h =
    ghbar_widget.hbar_new([
      ghbar_widget.item("a", 50),
      ghbar_widget.item("b", 80),
    ])
  ghbar_widget.render(buf, area, h, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn hbar_zero_area_test() {
  let area = rect_new(0, 0, 0, 0)
  let buf = buffer.buffer_new(area)
  let h = ghbar_widget.hbar_new([ghbar_widget.item("x", 10)])
  let result = ghbar_widget.render(buf, area, h, 0)
  buffer.width(result) |> should.equal(0)
}

pub fn hbar_empty_items_test() {
  let area = rect_new(0, 0, 20, 3)
  let buf = buffer.buffer_new(area)
  let h = ghbar_widget.hbar_new([])
  ghbar_widget.render(buf, area, h, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn hbar_solid_fill_test() {
  let area = rect_new(0, 0, 30, 3)
  let buf = buffer.buffer_new(area)
  let h =
    ghbar_widget.hbar_new([ghbar_widget.item("x", 50)])
    |> ghbar_widget.with_fill(
      ghbar_widget.HBarSolid([style.Rgb(255, 0, 0), style.Rgb(0, 255, 0)]),
    )
  ghbar_widget.render(buf, area, h, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn hbar_gradient_fill_test() {
  let area = rect_new(0, 0, 30, 3)
  let buf = buffer.buffer_new(area)
  let h =
    ghbar_widget.hbar_new([ghbar_widget.item("x", 75)])
    |> ghbar_widget.with_fill(
      ghbar_widget.HBarGradient([style.Rgb(0, 0, 255), style.Rgb(255, 0, 0)]),
    )
  ghbar_widget.render(buf, area, h, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn hbar_animated_rainbow_test() {
  let area = rect_new(0, 0, 30, 3)
  let buf = buffer.buffer_new(area)
  let h =
    ghbar_widget.hbar_new([ghbar_widget.item("x", 60)])
    |> ghbar_widget.with_fill(ghbar_widget.HBarAnimatedRainbow)
    |> ghbar_widget.with_period(60)
  ghbar_widget.render(buf, area, h, 30)
  |> buffer.area
  |> should.equal(area)
}

pub fn hbar_with_max_test() {
  let area = rect_new(0, 0, 25, 2)
  let buf = buffer.buffer_new(area)
  let h =
    ghbar_widget.hbar_new([ghbar_widget.item("a", 50)])
    |> ghbar_widget.with_max(200)
  ghbar_widget.render(buf, area, h, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn hbar_show_value_off_test() {
  let area = rect_new(0, 0, 25, 2)
  let buf = buffer.buffer_new(area)
  let h =
    ghbar_widget.hbar_new([ghbar_widget.item("a", 50)])
    |> ghbar_widget.with_show_value(False)
  ghbar_widget.render(buf, area, h, 0)
  |> buffer.area
  |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// Canvas widget tests

pub fn canvas_render_area_test() {
  let area = rect_new(0, 0, 20, 4)
  let buf = buffer.buffer_new(area)
  let c =
    gcanvas_widget.canvas_new([
      gcanvas_widget.series_new([10, 50, 30, 70, 20]),
    ])
  gcanvas_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn canvas_zero_area_test() {
  let area = rect_new(0, 0, 0, 0)
  let buf = buffer.buffer_new(area)
  let c = gcanvas_widget.canvas_new([gcanvas_widget.series_new([10, 20])])
  let result = gcanvas_widget.render(buf, area, c, 0)
  buffer.width(result) |> should.equal(0)
}

pub fn canvas_empty_series_test() {
  let area = rect_new(0, 0, 10, 4)
  let buf = buffer.buffer_new(area)
  let c = gcanvas_widget.canvas_new([])
  gcanvas_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn canvas_single_point_test() {
  let area = rect_new(0, 0, 10, 4)
  let buf = buffer.buffer_new(area)
  let c = gcanvas_widget.canvas_new([gcanvas_widget.series_new([50])])
  gcanvas_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn canvas_solid_fill_test() {
  let area = rect_new(0, 0, 15, 4)
  let buf = buffer.buffer_new(area)
  let c =
    gcanvas_widget.canvas_new([
      gcanvas_widget.series_new([0, 50, 100])
      |> gcanvas_widget.with_series_fill(
        gcanvas_widget.SeriesSolid(style.Rgb(0, 200, 255)),
      ),
    ])
  gcanvas_widget.render(buf, area, c, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn canvas_animated_rainbow_test() {
  let area = rect_new(0, 0, 15, 4)
  let buf = buffer.buffer_new(area)
  let c =
    gcanvas_widget.canvas_new([
      gcanvas_widget.series_new([10, 90, 30, 70])
      |> gcanvas_widget.with_series_fill(gcanvas_widget.SeriesAnimatedRainbow),
    ])
    |> gcanvas_widget.with_period(60)
  gcanvas_widget.render(buf, area, c, 30)
  |> buffer.area
  |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// Scene widget tests

pub fn scene_render_area_test() {
  let area = rect_new(0, 0, 20, 6)
  let buf = buffer.buffer_new(area)
  let s =
    gscene_widget.scene_new([
      gscene_widget.CircleOutline(
        20,
        12,
        8,
        gscene_widget.SceneSolid(style.Rgb(255, 255, 0)),
      ),
    ])
  gscene_widget.render(buf, area, s, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn scene_zero_area_test() {
  let area = rect_new(0, 0, 0, 0)
  let buf = buffer.buffer_new(area)
  let s = gscene_widget.scene_new([])
  let result = gscene_widget.render(buf, area, s, 0)
  buffer.width(result) |> should.equal(0)
}

pub fn scene_empty_shapes_test() {
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let s = gscene_widget.scene_new([])
  gscene_widget.render(buf, area, s, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn scene_disc_test() {
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let s =
    gscene_widget.scene_new([
      gscene_widget.Disc(
        20,
        10,
        4,
        gscene_widget.SceneSolid(style.Rgb(255, 100, 0)),
      ),
    ])
  gscene_widget.render(buf, area, s, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn scene_planet_test() {
  let area = rect_new(0, 0, 20, 5)
  let buf = buffer.buffer_new(area)
  let s =
    gscene_widget.scene_new([
      gscene_widget.Planet(
        20,
        10,
        8,
        2,
        gscene_widget.SceneSolid(style.Rgb(60, 140, 255)),
        50,
      ),
    ])
  gscene_widget.render(buf, area, s, 25)
  |> buffer.area
  |> should.equal(area)
}

pub fn scene_mandelbrot_test() {
  let area = rect_new(0, 0, 12, 4)
  let buf = buffer.buffer_new(area)
  let s = gscene_widget.scene_new([gscene_widget.Mandelbrot(12)])
  gscene_widget.render(buf, area, s, 0)
  |> buffer.area
  |> should.equal(area)
}

pub fn scene_rainbow_circle_test() {
  let area = rect_new(0, 0, 15, 5)
  let buf = buffer.buffer_new(area)
  let s =
    gscene_widget.scene_new([
      gscene_widget.CircleOutline(15, 10, 6, gscene_widget.SceneAnimatedRainbow),
    ])
  gscene_widget.render(buf, area, s, 30)
  |> buffer.area
  |> should.equal(area)
}

// ─────────────────────────────────────────────────────────────────
// Buffer diff tests

pub fn diff_identical_buffers_test() {
  let area = rect_new(0, 0, 4, 2)
  let buf = buffer.buffer_new(area)
  buffer.diff(buf, buf) |> should.equal([])
}

pub fn diff_single_cell_change_test() {
  let area = rect_new(0, 0, 4, 1)
  let prev = buffer.buffer_new(area)
  let next =
    buffer.set_string(
      prev,
      Position(1, 0),
      "X",
      style.Default,
      style.Default,
      style.none(),
    )
  let ops = buffer.diff(prev, next)
  list.length(ops) |> should.equal(1)
}

pub fn diff_returns_patch_at_change_position_test() {
  let area = rect_new(0, 0, 6, 1)
  let prev = buffer.buffer_new(area)
  let next =
    buffer.set_string(
      prev,
      Position(2, 0),
      "AB",
      style.Default,
      style.Default,
      style.none(),
    )
  let ops = buffer.diff(prev, next)
  case ops {
    [buffer.Patch(pos, _), ..] -> pos.x |> should.equal(2)
    _ -> should.fail()
  }
}

pub fn diff_multi_row_change_test() {
  let area = rect_new(0, 0, 5, 3)
  let prev = buffer.buffer_new(area)
  let next =
    prev
    |> buffer.set_string(
      Position(0, 0),
      "row0",
      style.Default,
      style.Default,
      style.none(),
    )
    |> buffer.set_string(
      Position(0, 2),
      "row2",
      style.Default,
      style.Default,
      style.none(),
    )
  let ops = buffer.diff(prev, next)
  // At least one patch per changed row
  case list.length(ops) >= 2 {
    True -> Nil
    False -> should.fail()
  }
}

pub fn diff_same_text_no_op_test() {
  let area = rect_new(0, 0, 8, 1)
  let prev =
    buffer.set_string(
      buffer.buffer_new(area),
      Position(0, 0),
      "hi",
      style.Default,
      style.Default,
      style.none(),
    )
  let next =
    buffer.set_string(
      buffer.buffer_new(area),
      Position(0, 0),
      "hi",
      style.Default,
      style.Default,
      style.none(),
    )
  buffer.diff(prev, next) |> should.equal([])
}

// ─────────────────────────────────────────────────────────────────
// Cell-aware text padding tests

pub fn pad_right_ascii_test() {
  text.pad_right("ab", 5) |> should.equal("ab   ")
}

pub fn pad_right_no_pad_when_full_test() {
  text.pad_right("abcde", 5) |> should.equal("abcde")
}

pub fn pad_right_no_pad_when_overflow_test() {
  text.pad_right("abcdef", 5) |> should.equal("abcdef")
}

pub fn pad_left_ascii_test() {
  text.pad_left("ab", 5) |> should.equal("   ab")
}

pub fn align_center_ascii_test() {
  text.align("ab", 6, text.Center) |> should.equal("  ab  ")
}

pub fn align_center_odd_pad_test() {
  // 5 - 2 = 3 → 1 left, 2 right
  text.align("ab", 5, text.Center) |> should.equal(" ab  ")
}

pub fn codepoint_width_ascii_test() {
  text.codepoint_cell_width(0x41) |> should.equal(1)
}

pub fn codepoint_width_cjk_test() {
  text.codepoint_cell_width(0x4E2D) |> should.equal(2)
}

pub fn codepoint_width_emoji_test() {
  text.codepoint_cell_width(0x1F600) |> should.equal(2)
}

pub fn codepoint_width_combining_test() {
  text.codepoint_cell_width(0x0301) |> should.equal(0)
}

pub fn codepoint_width_zwj_test() {
  text.codepoint_cell_width(0x200D) |> should.equal(0)
}

pub fn codepoint_width_control_test() {
  text.codepoint_cell_width(0x07) |> should.equal(0)
}

// strip_ansi extended tests

pub fn strip_ansi_csi_cursor_test() {
  text.strip_ansi("hi\u{001B}[2Athere") |> should.equal("hithere")
}

pub fn strip_ansi_osc_bel_test() {
  text.strip_ansi("a\u{001B}]0;title\u{0007}b") |> should.equal("ab")
}

pub fn strip_ansi_osc_st_test() {
  text.strip_ansi("a\u{001B}]0;title\u{001B}\\b") |> should.equal("ab")
}

// ─────────────────────────────────────────────────────────────────
// geometry.hit_test

pub fn hit_test_inside_test() {
  geometry.hit_test(rect_new(2, 3, 5, 4), 4, 5) |> should.equal(True)
}

pub fn hit_test_on_left_edge_test() {
  geometry.hit_test(rect_new(2, 3, 5, 4), 2, 3) |> should.equal(True)
}

pub fn hit_test_outside_right_test() {
  geometry.hit_test(rect_new(2, 3, 5, 4), 7, 3) |> should.equal(False)
}

pub fn hit_test_outside_bottom_test() {
  geometry.hit_test(rect_new(2, 3, 5, 4), 2, 7) |> should.equal(False)
}

// ─────────────────────────────────────────────────────────────────
// text.wrap blank-line fix

pub fn wrap_blank_line_between_paragraphs_test() {
  text.wrap("a\n\nb", 80) |> should.equal(["a", "", "b"])
}

pub fn wrap_leading_newline_test() {
  text.wrap("\na", 80) |> should.equal(["", "a"])
}

pub fn wrap_trailing_newline_test() {
  text.wrap("a\n", 80) |> should.equal(["a", ""])
}

// ─────────────────────────────────────────────────────────────────
// buffer.to_ansi / diff_to_ansi

pub fn to_ansi_nonempty_test() {
  let area = rect_new(0, 0, 3, 1)
  let buf =
    buffer.buffer_new(area)
    |> buffer.set_string(
      Position(x: 0, y: 0),
      "abc",
      style.Default,
      style.Default,
      style.none(),
    )
  let result = buffer.to_ansi(buf)
  result |> string.contains("abc") |> should.equal(True)
}

pub fn diff_to_ansi_identical_buffers_test() {
  let area = rect_new(0, 0, 3, 1)
  let buf =
    buffer.buffer_new(area)
    |> buffer.set_string(
      Position(x: 0, y: 0),
      "abc",
      style.Default,
      style.Default,
      style.none(),
    )
  buffer.diff_to_ansi(buf, buf) |> should.equal("")
}

pub fn diff_to_ansi_single_change_test() {
  let area = rect_new(0, 0, 3, 1)
  let prev =
    buffer.buffer_new(area)
    |> buffer.set_string(
      Position(x: 0, y: 0),
      "abc",
      style.Default,
      style.Default,
      style.none(),
    )
  let curr =
    buffer.buffer_new(area)
    |> buffer.set_string(
      Position(x: 0, y: 0),
      "axc",
      style.Default,
      style.Default,
      style.none(),
    )
  let result = buffer.diff_to_ansi(prev, curr)
  result |> string.contains("x") |> should.equal(True)
  result |> string.contains("a") |> should.equal(False)
}

// ─────────────────────────────────────────────────────────────────
// table col_constraints

pub fn table_col_constraints_resolve_test() {
  let area = rect_new(0, 0, 40, 5)
  let t =
    gtable_widget.table_new([["Alice", "30"], ["Bob", "25"]])
    |> gtable_widget.with_col_constraints([
      geometry.Fill,
      geometry.Length(6),
    ])
  let buf = buffer.buffer_new(area)
  let result = gtable_widget.render(buf, area, t)
  buffer.width(result) |> should.equal(40)
}

// ─────────────────────────────────────────────────────────────────
// keys.match

pub fn keys_match_arrows_test() {
  keys.match("up") |> should.equal(keys.Up)
  keys.match("down") |> should.equal(keys.Down)
  keys.match("left") |> should.equal(keys.Left)
  keys.match("right") |> should.equal(keys.Right)
}

pub fn keys_match_control_keys_test() {
  keys.match("enter") |> should.equal(keys.Enter)
  keys.match("backspace") |> should.equal(keys.Backspace)
  keys.match("esc") |> should.equal(keys.Escape)
  keys.match("tab") |> should.equal(keys.Tab)
}

pub fn keys_match_function_keys_test() {
  keys.match("f1") |> should.equal(keys.F(1))
  keys.match("f12") |> should.equal(keys.F(12))
}

pub fn keys_match_ctrl_combo_test() {
  keys.match("ctrl+c") |> should.equal(keys.Ctrl("c"))
  keys.match("ctrl+d") |> should.equal(keys.Ctrl("d"))
}

pub fn keys_match_alt_combo_test() {
  keys.match("alt+f") |> should.equal(keys.Alt("f"))
}

pub fn keys_match_char_test() {
  keys.match("a") |> should.equal(keys.Char("a"))
  keys.match("€") |> should.equal(keys.Char("€"))
}

pub fn keys_is_char_test() {
  keys.is_char(keys.Char("a")) |> should.equal(True)
  keys.is_char(keys.Up) |> should.equal(False)
}

pub fn keys_char_value_test() {
  keys.char_value(keys.Char("x")) |> should.equal("x")
  keys.char_value(keys.Enter) |> should.equal("")
}

// ─────────────────────────────────────────────────────────────────
// style additions

pub fn style_add_modifier_test() {
  let s = style.default_style() |> style.add_modifier(style.bold())
  style.has(s.modifier, style.bold()) |> should.equal(True)
  style.has(s.modifier, style.italic()) |> should.equal(False)
}

pub fn style_remove_modifier_test() {
  let s =
    style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.add(style.bold(), style.italic()),
    )
    |> style.remove_modifier(style.bold())
  style.has(s.modifier, style.bold()) |> should.equal(False)
  style.has(s.modifier, style.italic()) |> should.equal(True)
}

pub fn style_italic_dim_underline_style_test() {
  style.has(style.italic_style().modifier, style.italic()) |> should.equal(True)
  style.has(style.dim_style().modifier, style.dim()) |> should.equal(True)
  style.has(style.underline_style().modifier, style.underline())
  |> should.equal(True)
}

pub fn style_color_from_hex_test() {
  style.color_from_hex("#1e1e2e") |> should.equal(Ok(style.Rgb(30, 30, 46)))
  style.color_from_hex("ff5555") |> should.equal(Ok(style.Rgb(255, 85, 85)))
  style.color_from_hex("FFFFFF") |> should.equal(Ok(style.Rgb(255, 255, 255)))
  style.color_from_hex("000000") |> should.equal(Ok(style.Rgb(0, 0, 0)))
}

pub fn style_color_from_hex_invalid_test() {
  style.color_from_hex("xyz") |> should.equal(Error(Nil))
  style.color_from_hex("#12345") |> should.equal(Error(Nil))
  style.color_from_hex("") |> should.equal(Error(Nil))
}

// ─────────────────────────────────────────────────────────────────
// geometry additions

pub fn geometry_split_h_v_test() {
  let area = rect_new(0, 0, 100, 20)
  let cols = geometry.split_h(area, [geometry.Fill, geometry.Fill])
  list.length(cols) |> should.equal(2)
  let col0 = case cols {
    [c, ..] -> c
    _ -> rect_new(0, 0, 0, 0)
  }
  col0.size.width |> should.equal(50)

  let rows = geometry.split_v(area, [geometry.Length(5), geometry.Fill])
  let row0 = case rows {
    [r, ..] -> r
    _ -> rect_new(0, 0, 0, 0)
  }
  row0.size.height |> should.equal(5)
}

pub fn geometry_centered_rect_test() {
  let area = rect_new(0, 0, 80, 24)
  let r = geometry.centered_rect(40, 10, area)
  r.size.width |> should.equal(40)
  r.size.height |> should.equal(10)
  r.position.x |> should.equal(20)
  r.position.y |> should.equal(7)
}

pub fn geometry_centered_rect_clamps_test() {
  let area = rect_new(0, 0, 10, 5)
  let r = geometry.centered_rect(200, 200, area)
  r.size.width |> should.equal(10)
  r.size.height |> should.equal(5)
}

pub fn geometry_percent_rect_test() {
  let area = rect_new(0, 0, 100, 40)
  let r = geometry.percent_rect(50, 50, area)
  r.size.width |> should.equal(50)
  r.size.height |> should.equal(20)
}

// ─────────────────────────────────────────────────────────────────
// span additions

pub fn span_bold_italic_dim_test() {
  style.has(span.span_bold("x").modifier, style.bold()) |> should.equal(True)
  style.has(span.span_italic("x").modifier, style.italic())
  |> should.equal(True)
  style.has(span.span_dim("x").modifier, style.dim()) |> should.equal(True)
  style.has(span.span_underline("x").modifier, style.underline())
  |> should.equal(True)
}

pub fn span_line_alignment_left_test() {
  let l = span.line_new([span.span_plain("hi")])
  l.alignment |> should.equal(text.Left)
}

pub fn span_line_aligned_center_test() {
  let l = span.line_aligned([span.span_plain("hi")], text.Center)
  l.alignment |> should.equal(text.Center)
}

pub fn span_line_render_right_aligned_test() {
  let area = rect_new(0, 0, 10, 1)
  let buf = buffer.buffer_new(area)
  let l = span.line_aligned([span.span_plain("AB")], text.Right)
  let result = span.render_line(buf, geometry.Position(x: 0, y: 0), l, 10)
  buffer.cell_symbol(buffer.get_cell(result, geometry.Position(x: 8, y: 0)))
  |> should.equal("A")
  buffer.cell_symbol(buffer.get_cell(result, geometry.Position(x: 9, y: 0)))
  |> should.equal("B")
}

// ─────────────────────────────────────────────────────────────────
// focus

pub fn focus_new_first_focused_test() {
  let ring = focus.focus_new(["a", "b", "c"])
  focus.focused(ring) |> should.equal(Ok("a"))
}

pub fn focus_next_advances_test() {
  let ring = focus.focus_new(["a", "b", "c"]) |> focus.focus_next
  focus.focused(ring) |> should.equal(Ok("b"))
}

pub fn focus_next_wraps_test() {
  let ring =
    focus.focus_new(["a", "b", "c"])
    |> focus.focus_next
    |> focus.focus_next
    |> focus.focus_next
  focus.focused(ring) |> should.equal(Ok("a"))
}

pub fn focus_prev_wraps_test() {
  let ring = focus.focus_new(["a", "b", "c"]) |> focus.focus_prev
  focus.focused(ring) |> should.equal(Ok("c"))
}

pub fn focus_is_focused_test() {
  let ring = focus.focus_new(["a", "b"])
  focus.is_focused(ring, "a") |> should.equal(True)
  focus.is_focused(ring, "b") |> should.equal(False)
}

pub fn focus_id_jump_test() {
  let ring = focus.focus_new(["a", "b", "c"]) |> focus.focus_id("c")
  focus.focused(ring) |> should.equal(Ok("c"))
}

pub fn focus_id_not_found_noop_test() {
  let ring = focus.focus_new(["a", "b"]) |> focus.focus_id("z")
  focus.focused(ring) |> should.equal(Ok("a"))
}

pub fn focus_empty_ring_test() {
  let ring = focus.focus_new([])
  focus.focused(ring) |> should.equal(Error(Nil))
  focus.is_focused(ring, "x") |> should.equal(False)
  focus.focus_next(ring) |> focus.focused |> should.equal(Error(Nil))
}

pub fn focus_size_test() {
  focus.size(focus.focus_new(["a", "b", "c"])) |> should.equal(3)
  focus.size(focus.focus_new([])) |> should.equal(0)
}

pub fn focus_index_test() {
  let ring = focus.focus_new(["a", "b", "c"]) |> focus.focus_index(2)
  focus.focused(ring) |> should.equal(Ok("c"))
  focus.current_index(ring) |> should.equal(2)
}

// ─────────────────────────────────────────────────────────────────
// textarea

pub fn textarea_state_new_test() {
  let s = textarea.state_new()
  textarea.value(s) |> should.equal("")
  textarea.line_count(s) |> should.equal(1)
}

pub fn textarea_insert_char_test() {
  let w = textarea.textarea_new()
  let s =
    textarea.state_new()
    |> textarea.insert_char(w, _, "h")
    |> textarea.insert_char(w, _, "i")
  textarea.value(s) |> should.equal("hi")
  s.cursor_x |> should.equal(2)
}

pub fn textarea_backspace_removes_char_test() {
  let w = textarea.textarea_new()
  let s =
    textarea.state_new()
    |> textarea.insert_char(w, _, "a")
    |> textarea.insert_char(w, _, "b")
    |> textarea.backspace
  textarea.value(s) |> should.equal("a")
}

pub fn textarea_backspace_at_start_noop_test() {
  let s = textarea.state_new() |> textarea.backspace
  textarea.value(s) |> should.equal("")
}

pub fn textarea_newline_splits_line_test() {
  let w = textarea.textarea_new()
  let s =
    textarea.state_new()
    |> textarea.insert_char(w, _, "a")
    |> textarea.insert_char(w, _, "b")
    |> textarea.newline(w, _)
    |> textarea.insert_char(w, _, "c")
  textarea.value(s) |> should.equal("ab\nc")
  textarea.line_count(s) |> should.equal(2)
}

pub fn textarea_backspace_merges_lines_test() {
  let w = textarea.textarea_new()
  let s =
    textarea.state_new()
    |> textarea.insert_char(w, _, "a")
    |> textarea.newline(w, _)
    |> textarea.backspace
  textarea.value(s) |> should.equal("a")
  textarea.line_count(s) |> should.equal(1)
}

pub fn textarea_state_from_string_test() {
  let s = textarea.state_from_string("hello\nworld")
  textarea.value(s) |> should.equal("hello\nworld")
  textarea.line_count(s) |> should.equal(2)
  s.cursor_y |> should.equal(1)
}

pub fn textarea_move_cursor_up_down_test() {
  let w = textarea.textarea_new()
  let s =
    textarea.state_new()
    |> textarea.insert_char(w, _, "a")
    |> textarea.newline(w, _)
    |> textarea.insert_char(w, _, "b")
  let s2 = textarea.move_cursor_up(s)
  s2.cursor_y |> should.equal(0)
  let s3 = textarea.move_cursor_down(s2)
  s3.cursor_y |> should.equal(1)
}

pub fn textarea_max_lines_limit_test() {
  let w = textarea.textarea_new() |> textarea.with_max_lines(2)
  let s =
    textarea.state_new()
    |> textarea.newline(w, _)
    |> textarea.newline(w, _)
  textarea.line_count(s) |> should.equal(2)
}

pub fn textarea_move_to_line_start_end_test() {
  let w = textarea.textarea_new()
  let s =
    textarea.state_new()
    |> textarea.insert_char(w, _, "a")
    |> textarea.insert_char(w, _, "b")
    |> textarea.move_to_line_start
  s.cursor_x |> should.equal(0)
  let s2 = textarea.move_to_line_end(s)
  s2.cursor_x |> should.equal(2)
}

// ─────────────────────────────────────────────────────────────────
// tree

pub fn tree_state_new_test() {
  let state = tree.state_new()
  tree.selected(state) |> should.equal(Error(Nil))
}

pub fn tree_state_from_tree_selects_first_test() {
  let t = tree.tree_new([tree.leaf("a", "A"), tree.leaf("b", "B")])
  let state = tree.state_from_tree(t)
  tree.selected(state) |> should.equal(Ok("a"))
}

pub fn tree_expand_collapse_test() {
  let state = tree.state_new()
  let s2 = tree.expand("src", state)
  tree.is_expanded(s2, "src") |> should.equal(True)
  let s3 = tree.collapse("src", s2)
  tree.is_expanded(s3, "src") |> should.equal(False)
}

pub fn tree_expand_idempotent_test() {
  let s =
    tree.state_new()
    |> tree.expand("src", _)
    |> tree.expand("src", _)
  list.length(s.expanded) |> should.equal(1)
}

pub fn tree_toggle_selected_test() {
  let t =
    tree.tree_new([
      tree.node("src", "src/", [tree.leaf("main", "main.gleam")]),
    ])
  let state = tree.state_from_tree(t)
  tree.is_expanded(state, "src") |> should.equal(False)
  let s2 = tree.toggle_selected(state, t)
  tree.is_expanded(s2, "src") |> should.equal(True)
  let s3 = tree.toggle_selected(s2, t)
  tree.is_expanded(s3, "src") |> should.equal(False)
}

pub fn tree_toggle_leaf_noop_test() {
  let t = tree.tree_new([tree.leaf("readme", "README.md")])
  let state = tree.TreeState(expanded: [], selected: "readme")
  let s2 = tree.toggle_selected(state, t)
  tree.is_expanded(s2, "readme") |> should.equal(False)
}

pub fn tree_select_next_test() {
  let t =
    tree.tree_new([
      tree.leaf("a", "A"),
      tree.leaf("b", "B"),
      tree.leaf("c", "C"),
    ])
  let state = tree.TreeState(expanded: [], selected: "a")
  let s2 = tree.select_next(state, t)
  tree.selected(s2) |> should.equal(Ok("b"))
}

pub fn tree_select_prev_test() {
  let t =
    tree.tree_new([
      tree.leaf("a", "A"),
      tree.leaf("b", "B"),
    ])
  let state = tree.TreeState(expanded: [], selected: "b")
  let s2 = tree.select_prev(state, t)
  tree.selected(s2) |> should.equal(Ok("a"))
}

pub fn tree_select_next_at_end_noop_test() {
  let t = tree.tree_new([tree.leaf("a", "A"), tree.leaf("b", "B")])
  let state = tree.TreeState(expanded: [], selected: "b")
  let s2 = tree.select_next(state, t)
  tree.selected(s2) |> should.equal(Ok("b"))
}

pub fn tree_expanded_children_visible_in_nav_test() {
  let t =
    tree.tree_new([
      tree.node("src", "src/", [tree.leaf("main", "main.gleam")]),
      tree.leaf("readme", "README.md"),
    ])
  let state =
    tree.TreeState(expanded: ["src"], selected: "src")
    |> tree.select_next(t)
  tree.selected(state) |> should.equal(Ok("main"))
}

// ─────────────────────────────────────────────────────────────────
// scroll_view

pub fn scroll_view_state_new_test() {
  let s = scroll_view.sv_state_new()
  s.scroll_x |> should.equal(0)
  s.scroll_y |> should.equal(0)
}

pub fn scroll_view_scroll_down_test() {
  let s = scroll_view.sv_state_new() |> scroll_view.scroll_down(5)
  s.scroll_y |> should.equal(5)
}

pub fn scroll_view_scroll_up_clamps_test() {
  let s =
    scroll_view.sv_state_new()
    |> scroll_view.scroll_down(3)
    |> scroll_view.scroll_up(10)
  s.scroll_y |> should.equal(0)
}

pub fn scroll_view_scroll_right_left_test() {
  let s =
    scroll_view.sv_state_new()
    |> scroll_view.scroll_right(4)
    |> scroll_view.scroll_left(2)
  s.scroll_x |> should.equal(2)
}

pub fn scroll_view_clamp_test() {
  let sv = scroll_view.scroll_view_new(20, 20)
  let s = scroll_view.scroll_to(scroll_view.sv_state_new(), 100, 100)
  let clamped = scroll_view.clamp(s, sv, 10, 10)
  clamped.scroll_x |> should.equal(10)
  clamped.scroll_y |> should.equal(10)
}

pub fn scroll_view_scroll_to_test() {
  let s = scroll_view.scroll_to(scroll_view.sv_state_new(), 7, 3)
  s.scroll_x |> should.equal(7)
  s.scroll_y |> should.equal(3)
}

pub fn scroll_view_pct_y_test() {
  let sv = scroll_view.scroll_view_new(100, 100)
  let s = scroll_view.scroll_to(scroll_view.sv_state_new(), 0, 50)
  scroll_view.scroll_pct_y(s, sv, 10) |> should.equal(55)
}

pub fn scroll_view_pct_x_test() {
  let sv = scroll_view.scroll_view_new(100, 100)
  let s = scroll_view.scroll_to(scroll_view.sv_state_new(), 0, 0)
  scroll_view.scroll_pct_x(s, sv, 100) |> should.equal(0)
}

pub fn scroll_view_render_blits_content_test() {
  let area = rect_new(0, 0, 5, 3)
  let buf = buffer.buffer_new(area)
  let sv = scroll_view.scroll_view_new(10, 5)
  let state = scroll_view.sv_state_new()
  let result =
    scroll_view.render(buf, area, sv, state, fn(inner_buf, _inner_area) {
      buffer.set_string(
        inner_buf,
        geometry.Position(x: 0, y: 0),
        "Hello",
        style.Default,
        style.Default,
        style.none(),
      )
      |> buffer.set_string(
        geometry.Position(x: 0, y: 1),
        "World",
        style.Default,
        style.Default,
        style.none(),
      )
    })
  buffer.width(result) |> should.equal(5)
  buffer.height(result) |> should.equal(3)
}

// ─────────────────────────────────────────────────────────────────
// UndoStack tests

pub fn undo_new_has_initial_test() {
  let s = undo.undo_new("hello", max_size: 10)
  undo.current(s) |> should.equal("hello")
}

pub fn undo_can_undo_false_initially_test() {
  let s = undo.undo_new(0, max_size: 10)
  undo.can_undo(s) |> should.equal(False)
}

pub fn undo_can_undo_after_push_test() {
  let s = undo.undo_new(0, max_size: 10) |> undo.push(1)
  undo.can_undo(s) |> should.equal(True)
}

pub fn undo_undo_restores_previous_test() {
  let s =
    undo.undo_new(0, max_size: 10)
    |> undo.push(1)
    |> undo.push(2)
    |> undo.undo
  undo.current(s) |> should.equal(1)
}

pub fn undo_redo_restores_future_test() {
  let s =
    undo.undo_new(0, max_size: 10)
    |> undo.push(1)
    |> undo.push(2)
    |> undo.undo
    |> undo.redo
  undo.current(s) |> should.equal(2)
}

pub fn undo_push_clears_future_test() {
  let s =
    undo.undo_new(0, max_size: 10)
    |> undo.push(1)
    |> undo.undo
    |> undo.push(2)
  undo.can_redo(s) |> should.equal(False)
  undo.current(s) |> should.equal(2)
}

pub fn undo_noop_on_empty_past_test() {
  let s = undo.undo_new(42, max_size: 10) |> undo.undo
  undo.current(s) |> should.equal(42)
}

pub fn undo_noop_on_empty_future_test() {
  let s = undo.undo_new(42, max_size: 10) |> undo.redo
  undo.current(s) |> should.equal(42)
}

pub fn undo_max_size_trims_past_test() {
  let s =
    undo.undo_new(0, max_size: 2)
    |> undo.push(1)
    |> undo.push(2)
    |> undo.push(3)
  undo.undo_depth(s) |> should.equal(2)
}

pub fn undo_reset_clears_all_test() {
  let s =
    undo.undo_new(0, max_size: 10)
    |> undo.push(1)
    |> undo.push(2)
    |> undo.reset(99)
  undo.current(s) |> should.equal(99)
  undo.can_undo(s) |> should.equal(False)
  undo.can_redo(s) |> should.equal(False)
}

// ─────────────────────────────────────────────────────────────────
// Keymap tests

pub fn keymap_lookup_found_test() {
  let km =
    keymap.keymap_new()
    |> keymap.bind("ctrl+q", "quit", "Quit")
    |> keymap.bind("ctrl+s", "save", "Save")
  keymap.lookup(km, "ctrl+q") |> should.equal(Ok("quit"))
}

pub fn keymap_lookup_not_found_test() {
  let km = keymap.keymap_new() |> keymap.bind("ctrl+q", "quit", "Quit")
  keymap.lookup(km, "ctrl+x") |> should.equal(Error(Nil))
}

pub fn keymap_first_binding_wins_test() {
  let km =
    keymap.keymap_new()
    |> keymap.bind("a", "first", "First")
    |> keymap.bind("a", "second", "Second")
  keymap.lookup(km, "a") |> should.equal(Ok("first"))
}

pub fn keymap_unbind_removes_key_test() {
  let km =
    keymap.keymap_new()
    |> keymap.bind("ctrl+q", "quit", "Quit")
    |> keymap.unbind("ctrl+q")
  keymap.lookup(km, "ctrl+q") |> should.equal(Error(Nil))
}

pub fn keymap_merge_combines_bindings_test() {
  let km1 = keymap.keymap_new() |> keymap.bind("a", "aa", "A")
  let km2 = keymap.keymap_new() |> keymap.bind("b", "bb", "B")
  let merged = keymap.merge(km1, km2)
  keymap.lookup(merged, "a") |> should.equal(Ok("aa"))
  keymap.lookup(merged, "b") |> should.equal(Ok("bb"))
}

pub fn keymap_help_lines_order_test() {
  let km =
    keymap.keymap_new()
    |> keymap.bind("a", 1, "Alpha")
    |> keymap.bind("b", 2, "Beta")
  let lines = keymap.help_lines(km)
  lines |> should.equal([#("a", "Alpha"), #("b", "Beta")])
}

pub fn keymap_filter_by_description_test() {
  let km =
    keymap.keymap_new()
    |> keymap.bind("ctrl+q", "quit", "Quit application")
    |> keymap.bind("ctrl+s", "save", "Save file")
    |> keymap.bind("ctrl+o", "open", "Open file")
  let filtered = keymap.filter(km, "file")
  list.length(keymap.help_lines(filtered)) |> should.equal(2)
}

pub fn keymap_filter_empty_returns_all_test() {
  let km =
    keymap.keymap_new()
    |> keymap.bind("a", 1, "Alpha")
    |> keymap.bind("b", 2, "Beta")
  let filtered = keymap.filter(km, "")
  list.length(keymap.help_lines(filtered)) |> should.equal(2)
}

// ─────────────────────────────────────────────────────────────────
// Dialog tests

pub fn dialog_state_initial_focus_confirm_test() {
  dialog.state_new().focused |> should.equal(dialog.Confirm)
}

pub fn dialog_toggle_confirm_to_cancel_test() {
  dialog.state_new()
  |> dialog.toggle
  |> should.equal(dialog.DialogState(focused: dialog.Cancel))
}

pub fn dialog_toggle_cancel_to_confirm_test() {
  dialog.state_new()
  |> dialog.toggle
  |> dialog.toggle
  |> should.equal(dialog.DialogState(focused: dialog.Confirm))
}

pub fn dialog_is_confirmed_true_when_confirm_focused_test() {
  dialog.state_new() |> dialog.is_confirmed |> should.equal(True)
}

pub fn dialog_is_confirmed_false_after_cancel_test() {
  dialog.state_new()
  |> dialog.cancel
  |> dialog.is_confirmed
  |> should.equal(False)
}

pub fn dialog_focus_confirm_sets_confirm_test() {
  dialog.state_new()
  |> dialog.cancel
  |> dialog.focus_confirm
  |> dialog.is_confirmed
  |> should.equal(True)
}

pub fn dialog_render_no_crash_test() {
  let area = rect_new(0, 0, 40, 10)
  let buf = buffer.buffer_new(area)
  let d = dialog.dialog_new("Delete?")
  let state = dialog.state_new()
  let result = dialog.render(buf, area, d, state)
  buffer.width(result) |> should.equal(40)
}

pub fn dialog_render_small_area_no_crash_test() {
  let area = rect_new(0, 0, 5, 2)
  let buf = buffer.buffer_new(area)
  let d = dialog.dialog_new("?")
  let result = dialog.render(buf, area, d, dialog.state_new())
  buffer.width(result) |> should.equal(5)
}

// ─────────────────────────────────────────────────────────────────
// Notification tests

pub fn notif_push_adds_item_test() {
  let q =
    gnotif_widget.queue_new(max: 5)
    |> gnotif_widget.push(gnotif_widget.info("hello", ttl: 10))
  gnotif_widget.count(q) |> should.equal(1)
}

pub fn notif_push_respects_max_test() {
  let q =
    gnotif_widget.queue_new(max: 2)
    |> gnotif_widget.push(gnotif_widget.info("a", ttl: 10))
    |> gnotif_widget.push(gnotif_widget.info("b", ttl: 10))
    |> gnotif_widget.push(gnotif_widget.info("c", ttl: 10))
  gnotif_widget.count(q) |> should.equal(2)
}

pub fn notif_tick_decrements_ttl_test() {
  let q =
    gnotif_widget.queue_new(max: 5)
    |> gnotif_widget.push(gnotif_widget.info("hi", ttl: 3))
    |> gnotif_widget.tick
    |> gnotif_widget.tick
  gnotif_widget.count(q) |> should.equal(1)
}

pub fn notif_tick_removes_expired_test() {
  let q =
    gnotif_widget.queue_new(max: 5)
    |> gnotif_widget.push(gnotif_widget.info("bye", ttl: 1))
    |> gnotif_widget.tick
  gnotif_widget.count(q) |> should.equal(0)
}

pub fn notif_persistent_never_expires_test() {
  let q =
    gnotif_widget.queue_new(max: 5)
    |> gnotif_widget.push(gnotif_widget.persistent("stay", gnotif_widget.Info))
    |> gnotif_widget.tick
    |> gnotif_widget.tick
    |> gnotif_widget.tick
  gnotif_widget.count(q) |> should.equal(1)
}

pub fn notif_dismiss_all_clears_test() {
  let q =
    gnotif_widget.queue_new(max: 5)
    |> gnotif_widget.push(gnotif_widget.info("a", ttl: 10))
    |> gnotif_widget.push(gnotif_widget.error("b", ttl: -1))
    |> gnotif_widget.dismiss_all
  gnotif_widget.count(q) |> should.equal(0)
}

pub fn notif_dismiss_level_test() {
  let q =
    gnotif_widget.queue_new(max: 5)
    |> gnotif_widget.push(gnotif_widget.info("a", ttl: 10))
    |> gnotif_widget.push(gnotif_widget.error("b", ttl: -1))
    |> gnotif_widget.dismiss_level(gnotif_widget.Error)
  gnotif_widget.count(q) |> should.equal(1)
}

pub fn notif_has_notifications_test() {
  let q = gnotif_widget.queue_new(max: 5)
  gnotif_widget.has_notifications(q) |> should.equal(False)
  let q2 = q |> gnotif_widget.push(gnotif_widget.info("x", ttl: 5))
  gnotif_widget.has_notifications(q2) |> should.equal(True)
}

pub fn notif_render_no_crash_test() {
  let area = rect_new(0, 0, 80, 24)
  let buf = buffer.buffer_new(area)
  let q =
    gnotif_widget.queue_new(max: 5)
    |> gnotif_widget.push(gnotif_widget.success("Saved!", ttl: 30))
    |> gnotif_widget.push(gnotif_widget.warning("Low disk", ttl: 30))
  let result = gnotif_widget.render(buf, area, q)
  buffer.width(result) |> should.equal(80)
}

// ─────────────────────────────────────────────────────────────────
// Form tests

pub fn form_initial_empty_test() {
  let f = gform_widget.form_new()
  gform_widget.values(f) |> should.equal([])
}

pub fn form_add_field_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_optional("name", "Name", "")
  gform_widget.get_value(f, "name") |> should.equal("")
}

pub fn form_type_char_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_optional("name", "Name", "")
    |> gform_widget.type_char("H")
    |> gform_widget.type_char("i")
  gform_widget.get_value(f, "name") |> should.equal("Hi")
}

pub fn form_backspace_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_optional("name", "Name", "")
    |> gform_widget.type_char("H")
    |> gform_widget.type_char("i")
    |> gform_widget.backspace
  gform_widget.get_value(f, "name") |> should.equal("H")
}

pub fn form_focus_next_wraps_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_optional("a", "A", "")
    |> gform_widget.add_optional("b", "B", "")
    |> gform_widget.focus_next
    |> gform_widget.focus_next
  f.focused |> should.equal(0)
}

pub fn form_focus_prev_wraps_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_optional("a", "A", "")
    |> gform_widget.add_optional("b", "B", "")
    |> gform_widget.focus_prev
  f.focused |> should.equal(1)
}

pub fn form_is_valid_optional_fields_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_optional("a", "A", "")
  gform_widget.is_valid(f) |> should.equal(True)
}

pub fn form_is_valid_required_empty_false_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_required("a", "A", "")
  gform_widget.is_valid(f) |> should.equal(False)
}

pub fn form_is_valid_required_filled_true_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_required("a", "A", "")
    |> gform_widget.set_value("a", "hello")
  gform_widget.is_valid(f) |> should.equal(True)
}

pub fn form_submit_marks_submitted_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_optional("a", "A", "value")
    |> gform_widget.submit
  gform_widget.is_submitted(f) |> should.equal(True)
}

pub fn form_submit_invalid_not_submitted_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_required("a", "A", "")
    |> gform_widget.submit
  gform_widget.is_submitted(f) |> should.equal(False)
}

pub fn form_validate_populates_errors_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_required("a", "A", "")
    |> gform_widget.validate
  case f.fields {
    [field, ..] -> field.error |> should.equal("required")
    [] -> should.fail()
  }
}

pub fn form_reset_clears_all_test() {
  let f =
    gform_widget.form_new()
    |> gform_widget.add_optional("a", "A", "")
    |> gform_widget.set_value("a", "hello")
    |> gform_widget.submit
    |> gform_widget.reset
  gform_widget.get_value(f, "a") |> should.equal("")
  gform_widget.is_submitted(f) |> should.equal(False)
}

pub fn form_render_no_crash_test() {
  let area = rect_new(0, 0, 40, 10)
  let buf = buffer.buffer_new(area)
  let f =
    gform_widget.form_new()
    |> gform_widget.add_required("name", "Name", "")
    |> gform_widget.add_optional("email", "Email", "")
  let result = gform_widget.render(buf, area, f)
  buffer.width(result) |> should.equal(40)
}

// ─────────────────────────────────────────────────────────────────
// split_responsive tests

pub fn split_responsive_wide_picks_first_breakpoint_test() {
  let area = rect_new(0, 0, 100, 10)
  let rects =
    geometry.split_responsive(area, [
      geometry.Breakpoint(80, [geometry.Percentage(50), geometry.Percentage(50)]),
      geometry.Breakpoint(0, [geometry.Percentage(100)]),
    ])
  list.length(rects) |> should.equal(2)
}

pub fn split_responsive_narrow_picks_fallback_test() {
  let area = rect_new(0, 0, 40, 10)
  let rects =
    geometry.split_responsive(area, [
      geometry.Breakpoint(80, [geometry.Percentage(50), geometry.Percentage(50)]),
      geometry.Breakpoint(0, [geometry.Percentage(100)]),
    ])
  list.length(rects) |> should.equal(1)
}

pub fn split_responsive_empty_breakpoints_returns_area_test() {
  let area = rect_new(0, 0, 80, 10)
  let rects = geometry.split_responsive(area, [])
  rects |> should.equal([area])
}

pub fn split_responsive_exact_boundary_test() {
  let area = rect_new(0, 0, 80, 10)
  let rects =
    geometry.split_responsive(area, [
      geometry.Breakpoint(80, [geometry.Percentage(50), geometry.Percentage(50)]),
      geometry.Breakpoint(0, [geometry.Percentage(100)]),
    ])
  list.length(rects) |> should.equal(2)
}
