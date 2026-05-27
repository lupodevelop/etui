/// Tests for the public viewport helpers added to textarea, table, and tree.
import etui/geometry.{Position, Rect, Size}
import etui/widgets/list as list_w
import etui/widgets/table
import etui/widgets/textarea as ta
import etui/widgets/tree
import gleeunit/should

// ─────────────────────────────────────────────────────────────────
// textarea.effective_offset

pub fn textarea_effective_offset_no_scroll_test() {
  let state = ta.state_from_string("a\nb\nc")
  ta.effective_offset(state, 10)
  |> should.equal(0)
}

pub fn textarea_effective_offset_cursor_at_boundary_test() {
  // cursor_y = 9, visible = 10: still fits (0..9), scroll = 0
  let state = ta.TextAreaState(lines: ["x"], cursor_x: 0, cursor_y: 9)
  ta.effective_offset(state, 10)
  |> should.equal(0)
}

pub fn textarea_effective_offset_cursor_past_boundary_test() {
  // cursor_y = 10, visible = 10: scroll = 10 - 10 + 1 = 1
  let state = ta.TextAreaState(lines: ["x"], cursor_x: 0, cursor_y: 10)
  ta.effective_offset(state, 10)
  |> should.equal(1)
}

pub fn textarea_effective_offset_zero_height_test() {
  let state = ta.TextAreaState(lines: ["x"], cursor_x: 0, cursor_y: 5)
  ta.effective_offset(state, 0)
  |> should.equal(0)
}

// ─────────────────────────────────────────────────────────────────
// textarea.cursor_screen_pos

pub fn cursor_screen_pos_visible_test() {
  let state = ta.TextAreaState(lines: ["hello"], cursor_x: 3, cursor_y: 0)
  let area =
    Rect(position: Position(x: 2, y: 5), size: Size(width: 20, height: 10))
  ta.cursor_screen_pos(state, area)
  |> should.equal(Ok(Position(x: 5, y: 5)))
}

pub fn cursor_screen_pos_with_scroll_test() {
  // cursor_y = 12, visible_h = 10, scroll = 3 → screen_y = 5 + 12 - 3 = 14
  let state = ta.TextAreaState(lines: ["x"], cursor_x: 1, cursor_y: 12)
  let area =
    Rect(position: Position(x: 0, y: 5), size: Size(width: 80, height: 10))
  ta.cursor_screen_pos(state, area)
  |> should.equal(Ok(Position(x: 1, y: 14)))
}

pub fn cursor_screen_pos_off_screen_horizontal_test() {
  // cursor_x >= width → Error(Nil), matching render rule
  let state = ta.TextAreaState(lines: ["x"], cursor_x: 20, cursor_y: 0)
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 20, height: 10))
  ta.cursor_screen_pos(state, area)
  |> should.equal(Error(Nil))
}

pub fn cursor_screen_pos_at_width_boundary_test() {
  // cursor_x == width is off-screen (render checks cursor_x < width)
  let state = ta.TextAreaState(lines: ["x"], cursor_x: 10, cursor_y: 0)
  let area =
    Rect(position: Position(x: 0, y: 0), size: Size(width: 10, height: 5))
  ta.cursor_screen_pos(state, area)
  |> should.equal(Error(Nil))
}

// ─────────────────────────────────────────────────────────────────
// table.effective_offset

pub fn table_effective_offset_no_scroll_test() {
  let state = table.TableState(selected_row: 3, offset: 0)
  table.effective_offset(state, 10)
  |> should.equal(0)
}

pub fn table_effective_offset_scrolled_test() {
  // selected = 12, offset = 0, visible = 10 → new offset = 12 - 10 + 1 = 3
  let state = table.TableState(selected_row: 12, offset: 0)
  table.effective_offset(state, 10)
  |> should.equal(3)
}

pub fn table_effective_offset_zero_height_test() {
  let state = table.TableState(selected_row: 5, offset: 0)
  table.effective_offset(state, 0)
  |> should.equal(0)
}

// ─────────────────────────────────────────────────────────────────
// list.effective_offset (already existed; verify contract still holds)

pub fn list_effective_offset_no_scroll_test() {
  let state = list_w.ListState(selected: 2, offset: 0)
  list_w.effective_offset(state, 10)
  |> should.equal(0)
}

pub fn list_effective_offset_scrolled_test() {
  let state = list_w.ListState(selected: 15, offset: 0)
  list_w.effective_offset(state, 10)
  |> should.equal(6)
}

// ─────────────────────────────────────────────────────────────────
// tree.visible_row_count

pub fn tree_visible_row_count_empty_test() {
  let t = tree.tree_new([])
  let state = tree.state_new()
  tree.visible_row_count(state, t)
  |> should.equal(0)
}

pub fn tree_visible_row_count_roots_only_test() {
  let t =
    tree.tree_new([
      tree.leaf("a", "A"),
      tree.leaf("b", "B"),
      tree.leaf("c", "C"),
    ])
  let state = tree.state_new()
  tree.visible_row_count(state, t)
  |> should.equal(3)
}

pub fn tree_visible_row_count_collapsed_test() {
  // Children hidden while collapsed
  let t =
    tree.tree_new([
      tree.node("src", "src/", [
        tree.leaf("m", "main.gleam"),
        tree.leaf("l", "lib.gleam"),
      ]),
      tree.leaf("r", "README.md"),
    ])
  let state = tree.state_new()
  tree.visible_row_count(state, t)
  |> should.equal(2)
}

pub fn tree_visible_row_count_expanded_test() {
  let t =
    tree.tree_new([
      tree.node("src", "src/", [
        tree.leaf("m", "main.gleam"),
        tree.leaf("l", "lib.gleam"),
      ]),
      tree.leaf("r", "README.md"),
    ])
  let state = tree.expand("src", tree.state_new())
  tree.visible_row_count(state, t)
  |> should.equal(4)
}

// ─────────────────────────────────────────────────────────────────
// tree.effective_offset

pub fn tree_effective_offset_zero_height_test() {
  let t = tree.tree_new([tree.leaf("a", "A"), tree.leaf("b", "B")])
  let state = tree.state_from_tree(t)
  tree.effective_offset(state, t, 0)
  |> should.equal(0)
}

pub fn tree_effective_offset_no_scroll_test() {
  let t =
    tree.tree_new([
      tree.leaf("a", "A"),
      tree.leaf("b", "B"),
      tree.leaf("c", "C"),
    ])
  let state = tree.state_from_tree(t)
  tree.effective_offset(state, t, 10)
  |> should.equal(0)
}

pub fn tree_effective_offset_scrolled_test() {
  // 5 items, selected = last, height = 3 → offset = 5 - 3 = 2
  let t =
    tree.tree_new([
      tree.leaf("a", "A"),
      tree.leaf("b", "B"),
      tree.leaf("c", "C"),
      tree.leaf("d", "D"),
      tree.leaf("e", "E"),
    ])
  let state = tree.TreeState(expanded: [], selected: "e")
  tree.effective_offset(state, t, 3)
  |> should.equal(2)
}
