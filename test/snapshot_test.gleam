// M3 snapshot tests: verify cell content, not just buffer area.
// Exit criterion: "rendering corretto di hello world in un blocco bordato, no terminale."

import etui/buffer
import etui/geometry.{Position, rect_new}
import etui/span
import etui/style
import etui/widgets/block
import etui/widgets/clear
import etui/widgets/gauge
import etui/widgets/input as input_widget
import etui/widgets/paragraph
import etui/widgets/scrollbar
import etui/widgets/sparkline
import etui/widgets/table as table_widget
import etui/widgets/tabs
import gleam/list
import gleam/string
import gleeunit/should

// ─── Helper ────────────────────────────────────────────────────────

/// Render buffer region to a multiline string.
/// Each row is one line; rows joined with "\n".
/// Unset cells appear as " " (empty_cell default).
fn buf_str(buf: buffer.Buffer) -> String {
  let area = buffer.area(buf)
  scan_rows(
    buf,
    area.position.x,
    area.position.y,
    area.size.width,
    area.size.height,
    0,
    [],
  )
  |> list.reverse
  |> string.join("\n")
}

fn scan_rows(
  buf: buffer.Buffer,
  ox: Int,
  oy: Int,
  w: Int,
  h: Int,
  row: Int,
  acc: List(String),
) -> List(String) {
  case row >= h {
    True -> acc
    False ->
      scan_rows(buf, ox, oy, w, h, row + 1, [
        scan_row(buf, ox, oy + row, w, 0, ""),
        ..acc
      ])
  }
}

fn scan_row(
  buf: buffer.Buffer,
  ox: Int,
  y: Int,
  w: Int,
  col: Int,
  acc: String,
) -> String {
  case col >= w {
    True -> acc
    False -> {
      let cell = buffer.get_cell(buf, Position(x: ox + col, y: y))
      // Skip Continuation cells — the wide grapheme was output at col-1
      let sym = case buffer.is_continuation(cell) {
        True -> ""
        False -> buffer.cell_symbol(cell)
      }
      scan_row(buf, ox, y, w, col + 1, acc <> sym)
    }
  }
}

// ─── Block border snapshots ────────────────────────────────────────

pub fn block_single_border_snapshot_test() {
  let area = rect_new(0, 0, 7, 3)
  let b = block.block_new() |> block.with_border(block.Single)
  buffer.buffer_new(area)
  |> block.render(area, b)
  |> buf_str
  |> should.equal("┌─────┐\n│     │\n└─────┘")
}

pub fn block_double_border_snapshot_test() {
  let area = rect_new(0, 0, 7, 3)
  let b = block.block_new() |> block.with_border(block.Double)
  buffer.buffer_new(area)
  |> block.render(area, b)
  |> buf_str
  |> should.equal("╔═════╗\n║     ║\n╚═════╝")
}

pub fn block_rounded_border_snapshot_test() {
  let area = rect_new(0, 0, 7, 3)
  let b = block.block_new() |> block.with_border(block.Rounded)
  buffer.buffer_new(area)
  |> block.render(area, b)
  |> buf_str
  |> should.equal("╭─────╮\n│     │\n╰─────╯")
}

pub fn block_no_border_snapshot_test() {
  // No border: inner area cleared, rest untouched (all spaces)
  let area = rect_new(0, 0, 5, 2)
  let b = block.block_new()
  buffer.buffer_new(area)
  |> block.render(area, b)
  |> buf_str
  |> should.equal("     \n     ")
}

// ─── Block with title ──────────────────────────────────────────────

pub fn block_title_top_snapshot_test() {
  // Title "Hi" written at x=1,y=0, overwrites border chars
  let area = rect_new(0, 0, 12, 3)
  let b =
    block.block_new()
    |> block.with_border(block.Single)
    |> block.with_title("Hi", block.Top)
  buffer.buffer_new(area)
  |> block.render(area, b)
  |> buf_str
  |> should.equal("┌Hi────────┐\n│          │\n└──────────┘")
}

pub fn block_title_bottom_snapshot_test() {
  let area = rect_new(0, 0, 12, 3)
  let b =
    block.block_new()
    |> block.with_border(block.Single)
    |> block.with_title("Hi", block.Bottom)
  buffer.buffer_new(area)
  |> block.render(area, b)
  |> buf_str
  |> should.equal("┌──────────┐\n│          │\n└Hi────────┘")
}

// ─── Paragraph snapshot ────────────────────────────────────────────

pub fn paragraph_single_line_snapshot_test() {
  // "hello" in 10×1: padded right to 10 cells
  let area = rect_new(0, 0, 10, 1)
  let p = paragraph.paragraph_new("hello")
  buffer.buffer_new(area)
  |> paragraph.render(area, p)
  |> buf_str
  |> should.equal("hello     ")
}

pub fn paragraph_wrapped_snapshot_test() {
  // "hello world" in 6×2: wraps to "hello " / "world " (aligned to 6)
  let area = rect_new(0, 0, 6, 2)
  let p = paragraph.paragraph_new("hello world")
  buffer.buffer_new(area)
  |> paragraph.render(area, p)
  |> buf_str
  |> should.equal("hello \nworld ")
}

pub fn paragraph_cjk_snapshot_test() {
  // "你好" = 4 cells in 6×1: padded to 6 cells (2 trailing spaces).
  // buf_str skips Continuation cells, so the string is 4 chars (你好 + 2 spaces).
  let area = rect_new(0, 0, 6, 1)
  let p = paragraph.paragraph_new("你好")
  buffer.buffer_new(area)
  |> paragraph.render(area, p)
  |> buf_str
  |> should.equal("你好  ")
}

// ─── M3 exit criterion: block + paragraph ─────────────────────────

pub fn block_with_paragraph_hello_world_test() {
  // THE exit criterion test.
  // 12×4 block (Single border) + "hello world" inside.
  // Inner area: x=1, y=1, width=10, height=2.
  // "hello world" wraps to ["hello", "world"], each padded to 10 cells.
  let area = rect_new(0, 0, 12, 4)
  let inner = rect_new(1, 1, 10, 2)
  let b = block.block_new() |> block.with_border(block.Single)
  let p = paragraph.paragraph_new("hello world")
  let buf =
    buffer.buffer_new(area)
    |> block.render(area, b)
    |> paragraph.render(inner, p)
  buf_str(buf)
  |> should.equal("┌──────────┐\n│hello     │\n│world     │\n└──────────┘")
}

pub fn block_with_cjk_content_test() {
  // 8×3 block + "你好" inside (4 cells), padded to 6
  let area = rect_new(0, 0, 8, 3)
  let inner = rect_new(1, 1, 6, 1)
  let b = block.block_new() |> block.with_border(block.Single)
  let p = paragraph.paragraph_new("你好")
  let buf =
    buffer.buffer_new(area)
    |> block.render(area, b)
    |> paragraph.render(inner, p)
  // Row 1: │ + 你(2 cells) + 好(2 cells) + 2 spaces + │ = 8 cells.
  // buf_str skips Continuation cells → "│你好  │" is 7 chars (not 8).
  buf_str(buf)
  |> should.equal("┌──────┐\n│你好  │\n└──────┘")
}

// ─── Diff snapshot tests ───────────────────────────────────────────

pub fn diff_identical_buffers_test() {
  // Identical buffers → 0 ops
  let area = rect_new(0, 0, 5, 2)
  let b = block.block_new() |> block.with_border(block.Single)
  let buf = buffer.buffer_new(area) |> block.render(area, b)
  buffer.diff(buf, buf) |> list.length |> should.equal(0)
}

pub fn diff_empty_to_block_test() {
  // Empty → bordered block: at least 1 op per row with content
  let area = rect_new(0, 0, 5, 3)
  let empty = buffer.buffer_new(area)
  let b = block.block_new() |> block.with_border(block.Single)
  let filled = block.render(empty, area, b)
  let ops = buffer.diff(empty, filled)
  // At minimum one op per row (3 rows, each has changed cells)
  { ops != [] } |> should.be_true
}

pub fn diff_one_cell_changed_test() {
  // Manually set one cell: diff should produce exactly 1 op
  let area = rect_new(0, 0, 5, 2)
  let prev = buffer.buffer_new(area)
  let next =
    buffer.set_cell(
      prev,
      Position(x: 2, y: 0),
      buffer.Cell(
        content: buffer.Content(symbol: "X", width: 1),
        fg: style.Default,
        bg: style.Default,
        modifier: style.none(),
        link: "",
      ),
    )
  let ops = buffer.diff(prev, next)
  list.length(ops) |> should.equal(1)
  case ops {
    [buffer.Patch(pos, cells)] -> {
      pos |> should.equal(Position(x: 2, y: 0))
      list.length(cells) |> should.equal(1)
    }
    _ -> should.fail()
  }
}

pub fn diff_full_row_changed_test() {
  // Change all cells in row 0: should produce 1 patch per changed run
  let area = rect_new(0, 0, 4, 2)
  let prev = buffer.buffer_new(area)
  let next =
    buffer.set_string(
      prev,
      Position(x: 0, y: 0),
      "abcd",
      style.Default,
      style.Default,
      style.none(),
    )
  let ops = buffer.diff(prev, next)
  // All 4 cells on row 0 changed and adjacent → 1 op
  list.length(ops) |> should.equal(1)
  case ops {
    [buffer.Patch(pos, cells)] -> {
      pos |> should.equal(Position(x: 0, y: 0))
      list.length(cells) |> should.equal(4)
    }
    _ -> should.fail()
  }
}

pub fn diff_full_screen_changed_test() {
  // Full screen change: expect height patches (one per row)
  let area = rect_new(0, 0, 4, 3)
  let prev = buffer.buffer_new(area)
  let next =
    buffer.set_string(
      prev,
      Position(x: 0, y: 0),
      "abcd",
      style.Default,
      style.Default,
      style.none(),
    )
    |> buffer.set_string(
      Position(x: 0, y: 1),
      "efgh",
      style.Default,
      style.Default,
      style.none(),
    )
    |> buffer.set_string(
      Position(x: 0, y: 2),
      "ijkl",
      style.Default,
      style.Default,
      style.none(),
    )
  let ops = buffer.diff(prev, next)
  // 3 rows changed → 3 patches
  list.length(ops) |> should.equal(3)
}

// ─── Buffer: non-zero origin ───────────────────────────────────────

pub fn block_at_nonzero_origin_test() {
  // Block at (5,2) — offset should not affect rendering
  let area = rect_new(5, 2, 7, 3)
  let b = block.block_new() |> block.with_border(block.Single)
  let buf = buffer.buffer_new(area)
  let result = block.render(buf, area, b)
  // Corner at (5,2) should be ┌
  buffer.get_cell(result, Position(x: 5, y: 2))
  |> buffer.cell_symbol
  |> should.equal("┌")
  // Corner at (11,2) should be ┐
  buffer.get_cell(result, Position(x: 11, y: 2))
  |> buffer.cell_symbol
  |> should.equal("┐")
  // Corner at (5,4) should be └
  buffer.get_cell(result, Position(x: 5, y: 4))
  |> buffer.cell_symbol
  |> should.equal("└")
  // Corner at (11,4) should be ┘
  buffer.get_cell(result, Position(x: 11, y: 4))
  |> buffer.cell_symbol
  |> should.equal("┘")
}

// ─── Clear widget ──────────────────────────────────────────────────

pub fn clear_erases_filled_area_test() {
  // Fill then clear: all cells become empty (space)
  let area = rect_new(0, 0, 5, 2)
  buffer.buffer_new(area)
  |> buffer.set_string(
    Position(x: 0, y: 0),
    "hello",
    style.Default,
    style.Default,
    style.none(),
  )
  |> buffer.set_string(
    Position(x: 0, y: 1),
    "world",
    style.Default,
    style.Default,
    style.none(),
  )
  |> clear.render(area)
  |> buf_str
  |> should.equal("     \n     ")
}

pub fn clear_partial_area_test() {
  // Clear only the bottom row; top row untouched
  let area = rect_new(0, 0, 5, 2)
  let bottom_row = rect_new(0, 1, 5, 1)
  buffer.buffer_new(area)
  |> buffer.set_string(
    Position(x: 0, y: 0),
    "hello",
    style.Default,
    style.Default,
    style.none(),
  )
  |> buffer.set_string(
    Position(x: 0, y: 1),
    "world",
    style.Default,
    style.Default,
    style.none(),
  )
  |> clear.render(bottom_row)
  |> buf_str
  |> should.equal("hello\n     ")
}

pub fn clear_empty_area_is_noop_test() {
  // clear on a zero-size rect does nothing
  let area = rect_new(0, 0, 5, 2)
  let noop = rect_new(0, 0, 0, 0)
  buffer.buffer_new(area)
  |> buffer.set_string(
    Position(x: 0, y: 0),
    "hello",
    style.Default,
    style.Default,
    style.none(),
  )
  |> clear.render(noop)
  |> buf_str
  |> should.equal("hello\n     ")
}

// ─── Gauge widget ──────────────────────────────────────────────────

pub fn gauge_50_percent_test() {
  // 10-cell wide bar at 50% → 5 filled, 5 empty
  let area = rect_new(0, 0, 10, 1)
  buffer.buffer_new(area)
  |> gauge.render(area, gauge.gauge_new(50))
  |> buf_str
  |> should.equal("█████░░░░░")
}

pub fn gauge_0_percent_test() {
  let area = rect_new(0, 0, 8, 1)
  buffer.buffer_new(area)
  |> gauge.render(area, gauge.gauge_new(0))
  |> buf_str
  |> should.equal("░░░░░░░░")
}

pub fn gauge_100_percent_test() {
  let area = rect_new(0, 0, 6, 1)
  buffer.buffer_new(area)
  |> gauge.render(area, gauge.gauge_new(100))
  |> buf_str
  |> should.equal("██████")
}

pub fn gauge_custom_chars_test() {
  let area = rect_new(0, 0, 4, 1)
  buffer.buffer_new(area)
  |> gauge.render(area, gauge.gauge_new(50) |> gauge.with_chars("=", "-"))
  |> buf_str
  |> should.equal("==--")
}

pub fn gauge_zero_area_is_noop_test() {
  let area = rect_new(0, 0, 0, 0)
  let buf = buffer.buffer_new(rect_new(0, 0, 5, 1))
  gauge.render(buf, area, gauge.gauge_new(50))
  |> buf_str
  |> should.equal("     ")
}

// ─── Tabs widget ───────────────────────────────────────────────────

pub fn tabs_renders_labels_test() {
  // Three tabs, active=0, width 20
  let area = rect_new(0, 0, 20, 1)
  let t = tabs.tabs_new(["Files", "Log", "Help"])
  buffer.buffer_new(area)
  |> tabs.render(area, t)
  |> buf_str
  // active tab has padding 1 each side: " Files " + "│" + " Log " + "│" + " Help "
  |> should.equal(" Files │ Log │ Help ")
}

pub fn tabs_active_index_test() {
  // Tab at index 1 is active — navigation helpers work
  let t =
    tabs.tabs_new(["A", "B", "C"])
    |> tabs.next_tab
  t.active
  |> should.equal(1)
}

pub fn tabs_wraps_around_test() {
  let t =
    tabs.tabs_new(["A", "B", "C"])
    |> tabs.with_active(2)
    |> tabs.next_tab
  t.active
  |> should.equal(0)
}

pub fn tabs_prev_wraps_test() {
  let t =
    tabs.tabs_new(["A", "B", "C"])
    |> tabs.prev_tab
  t.active
  |> should.equal(2)
}

// ─── Table widget ──────────────────────────────────────────────────

pub fn table_renders_rows_test() {
  // 2 rows × 2 cols, each col 5 wide → "alice│bob  \ncarol│dave "
  let area = rect_new(0, 0, 11, 2)
  let rows = [["alice", "bob"], ["carol", "dave"]]
  buffer.buffer_new(area)
  |> table_widget.render(
    area,
    table_widget.table_new(rows) |> table_widget.with_col_widths([5, 5]),
  )
  |> buf_str
  |> should.equal(" alic│bob  \n caro│dave ")
}

pub fn table_selection_prefix_test() {
  // Selected row 0 gets ▶ prefix, row 1 gets space
  let area = rect_new(0, 0, 11, 2)
  let rows = [["alice", "bob"], ["carol", "dave"]]
  let state = table_widget.state_new()
  buffer.buffer_new(area)
  |> table_widget.render_stateful(
    area,
    table_widget.table_new(rows) |> table_widget.with_col_widths([5, 5]),
    state,
  )
  |> buf_str
  |> should.equal("▶alic│bob  \n caro│dave ")
}

pub fn table_navigate_test() {
  let state =
    table_widget.state_new()
    |> table_widget.select_next_row(3)
    |> table_widget.select_next_row(3)
  state.selected_row
  |> should.equal(2)

  let state2 = table_widget.select_prev_row(state)
  state2.selected_row
  |> should.equal(1)
}

// ─── Sparkline widget ──────────────────────────────────────────────

pub fn sparkline_empty_data_test() {
  // No data → all spaces
  let area = rect_new(0, 0, 4, 1)
  buffer.buffer_new(area)
  |> sparkline.render(area, sparkline.sparkline_new([]), 0)
  |> buf_str
  |> should.equal("    ")
}

pub fn sparkline_max_value_test() {
  // All values equal max → all "█"
  let area = rect_new(0, 0, 3, 1)
  buffer.buffer_new(area)
  |> sparkline.render(
    area,
    sparkline.sparkline_new([10, 10, 10]) |> sparkline.with_max(10),
    0,
  )
  |> buf_str
  |> should.equal("███")
}

pub fn sparkline_zero_values_test() {
  // All zeros → all spaces
  let area = rect_new(0, 0, 3, 1)
  buffer.buffer_new(area)
  |> sparkline.render(
    area,
    sparkline.sparkline_new([0, 0, 0]) |> sparkline.with_max(10),
    0,
  )
  |> buf_str
  |> should.equal("   ")
}

// ─── Span / Line ───────────────────────────────────────────────────

pub fn span_plain_renders_test() {
  let area = rect_new(0, 0, 5, 1)
  let l = span.line_plain("hello")
  buffer.buffer_new(area)
  |> span.render_line(Position(x: 0, y: 0), l, 5)
  |> buf_str
  |> should.equal("hello")
}

pub fn span_multi_renders_test() {
  // Two spans concatenated: "hi" + "!!" = "hi!!"
  let area = rect_new(0, 0, 4, 1)
  let l = span.line_new([span.span_plain("hi"), span.span_plain("!!")])
  buffer.buffer_new(area)
  |> span.render_line(Position(x: 0, y: 0), l, 4)
  |> buf_str
  |> should.equal("hi!!")
}

pub fn span_clips_to_max_width_test() {
  // max_width=3 clips "hello" to "hel"
  let area = rect_new(0, 0, 5, 1)
  let l = span.line_plain("hello")
  buffer.buffer_new(area)
  |> span.render_line(Position(x: 0, y: 0), l, 3)
  |> buf_str
  |> should.equal("hel  ")
}

pub fn span_width_test() {
  span.span_width(span.span_plain("hello"))
  |> should.equal(5)
}

pub fn line_width_test() {
  let l = span.line_new([span.span_plain("hi"), span.span_plain("!!")])
  span.line_width(l)
  |> should.equal(4)
}

// ─── Input widget ──────────────────────────────────────────────────

pub fn input_renders_placeholder_test() {
  let area = rect_new(0, 0, 10, 1)
  let w = input_widget.input_new("search…")
  let state = input_widget.state_new()
  buffer.buffer_new(area)
  |> input_widget.render(area, w, state)
  |> buf_str
  |> should.equal("search…   ")
}

pub fn input_renders_value_test() {
  let area = rect_new(0, 0, 8, 1)
  let w = input_widget.input_new("")
  let state = input_widget.state_from_string("hello")
  buffer.buffer_new(area)
  |> input_widget.render(area, w, state)
  |> buf_str
  |> should.equal("hello   ")
}

pub fn input_insert_char_test() {
  let w = input_widget.input_new("")
  let s0 = input_widget.state_new()
  let s1 = input_widget.insert_char(w, s0, "a")
  let s2 = input_widget.insert_char(w, s1, "b")
  s2.value
  |> should.equal("ab")
  s2.cursor
  |> should.equal(2)
}

pub fn input_backspace_test() {
  let _w = input_widget.input_new("")
  let s = input_widget.state_from_string("hi")
  let s2 = input_widget.backspace(s)
  s2.value
  |> should.equal("h")
  s2.cursor
  |> should.equal(1)
}

pub fn input_backspace_at_start_noop_test() {
  let s = input_widget.state_new()
  let s2 = input_widget.backspace(s)
  s2.value
  |> should.equal("")
}

pub fn input_cursor_move_test() {
  let s = input_widget.state_from_string("abc")
  let s2 = input_widget.move_cursor_left(s)
  s2.cursor
  |> should.equal(2)
  let s3 = input_widget.move_cursor_right(s2)
  s3.cursor
  |> should.equal(3)
}

pub fn input_max_length_test() {
  let w = input_widget.input_new("") |> input_widget.with_max_length(2)
  let s0 = input_widget.state_new()
  let s1 = input_widget.insert_char(w, s0, "a")
  let s2 = input_widget.insert_char(w, s1, "b")
  let s3 = input_widget.insert_char(w, s2, "c")
  s3.value
  |> should.equal("ab")
}

// ─── Scrollbar widget ──────────────────────────────────────────────

pub fn scrollbar_vertical_thumb_at_top_test() {
  // 20 items, 4 visible, offset 0 → thumb at top
  let area = rect_new(0, 0, 1, 4)
  let s = scrollbar.scrollbar_new(20, 4, 0) |> scrollbar.with_arrows("", "")
  buffer.buffer_new(area)
  |> scrollbar.render_vertical(area, s)
  |> buf_str
  // thumb size = 4*4/20 = 0 → clamped to 1; at pos 0
  |> should.equal("█\n░\n░\n░")
}

pub fn scrollbar_vertical_thumb_at_bottom_test() {
  // offset = total - visible → thumb at bottom
  let area = rect_new(0, 0, 1, 4)
  let s = scrollbar.scrollbar_new(20, 4, 16) |> scrollbar.with_arrows("", "")
  buffer.buffer_new(area)
  |> scrollbar.render_vertical(area, s)
  |> buf_str
  |> should.equal("░\n░\n░\n█")
}

pub fn scrollbar_fully_visible_is_all_thumb_test() {
  // visible >= total → thumb fills entire track
  let area = rect_new(0, 0, 1, 4)
  let s = scrollbar.scrollbar_new(4, 4, 0) |> scrollbar.with_arrows("", "")
  buffer.buffer_new(area)
  |> scrollbar.render_vertical(area, s)
  |> buf_str
  |> should.equal("█\n█\n█\n█")
}

pub fn scrollbar_zero_area_noop_test() {
  let area = rect_new(0, 0, 0, 0)
  let buf = buffer.buffer_new(rect_new(0, 0, 2, 2))
  let s = scrollbar.scrollbar_new(10, 4, 0)
  scrollbar.render_vertical(buf, area, s)
  |> buf_str
  |> should.equal("  \n  ")
}

// ─── paragraph.render_styled ───────────────────────────────────────

pub fn paragraph_render_styled_test() {
  let area = rect_new(0, 0, 5, 2)
  let lines = [
    span.line_plain("hello"),
    span.line_plain("world"),
  ]
  buffer.buffer_new(area)
  |> paragraph.render_styled(area, lines)
  |> buf_str
  |> should.equal("hello\nworld")
}

pub fn paragraph_render_styled_clips_rows_test() {
  // 3 lines into area height 2 → only first 2 rendered
  let area = rect_new(0, 0, 5, 2)
  let lines = [
    span.line_plain("aaa"),
    span.line_plain("bbb"),
    span.line_plain("ccc"),
  ]
  buffer.buffer_new(area)
  |> paragraph.render_styled(area, lines)
  |> buf_str
  |> should.equal("aaa  \nbbb  ")
}

pub fn paragraph_render_styled_multi_span_test() {
  // Two spans on one row
  let area = rect_new(0, 0, 6, 1)
  let lines = [
    span.line_new([span.span_plain("foo"), span.span_plain("bar")]),
  ]
  buffer.buffer_new(area)
  |> paragraph.render_styled(area, lines)
  |> buf_str
  |> should.equal("foobar")
}
