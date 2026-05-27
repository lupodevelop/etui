/// Hierarchical tree widget with expand/collapse and keyboard navigation.
///
/// Nodes have a unique String `id`, a label, and optional children.
/// State tracks which nodes are expanded and which is selected.
///
/// ```gleam
/// import etui/widgets/tree
///
/// let t =
///   tree.tree_new([
///     tree.node("src", "src/", [
///       tree.leaf("main", "main.gleam"),
///       tree.leaf("lib",  "lib.gleam"),
///     ]),
///     tree.leaf("readme", "README.md"),
///   ])
///
/// let state = tree.state_new()
/// let state = tree.expand("src", state)    // expand node
/// let state = tree.select_next(state, t)   // move selection down
///
/// let buf = tree.render(buf, area, t, state)
///
/// // Read selection
/// tree.selected(state)  // Option(String), id of selected node
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

/// A tree node, either a leaf or an internal node with children.
/// `count` shows a right-aligned number after the label (e.g. unread count,
/// children count). `Error(Nil)` hides it.
pub type TreeNode {
  TreeNode(
    id: String,
    label: String,
    children: List(TreeNode),
    count: Result(Int, Nil),
  )
}

/// Tree widget configuration.
pub type TreeWidget {
  TreeWidget(
    roots: List(TreeNode),
    fg: style.Color,
    bg: style.Color,
    highlight_style: style.Style,
    /// Characters used to render the tree structure.
    glyphs: TreeGlyphs,
  )
}

/// Visual symbols for tree lines and expansion indicators.
pub type TreeGlyphs {
  TreeGlyphs(
    /// Prefix for collapsed node with children.
    collapsed: String,
    /// Prefix for expanded node with children.
    expanded: String,
    /// Prefix for leaf node.
    leaf: String,
    /// Indent per depth level (repeated).
    indent: String,
  )
}

/// State: which nodes are expanded, which is selected.
pub type TreeState {
  TreeState(
    /// IDs of expanded nodes.
    expanded: List(String),
    /// ID of currently selected node.
    selected: String,
  )
}

// ─────────────────────────────────────────────────────────────────
// Glyph sets

/// Default Unicode glyphs (▶ ▼ and box-drawing indent).
pub fn default_glyphs() -> TreeGlyphs {
  TreeGlyphs(collapsed: "▶ ", expanded: "▼ ", leaf: "  ", indent: "  ")
}

/// ASCII-safe glyphs for terminals without Unicode support.
pub fn ascii_glyphs() -> TreeGlyphs {
  TreeGlyphs(collapsed: "+ ", expanded: "- ", leaf: "  ", indent: "  ")
}

// ─────────────────────────────────────────────────────────────────
// Node constructors

/// Create a leaf node (no children).
pub fn leaf(id: String, label: String) -> TreeNode {
  TreeNode(id: id, label: label, children: [], count: Error(Nil))
}

/// Create an internal node with children.
pub fn node(id: String, label: String, children: List(TreeNode)) -> TreeNode {
  TreeNode(id: id, label: label, children: children, count: Error(Nil))
}

/// Leaf with a right-aligned count.
pub fn leaf_with_count(id: String, label: String, count: Int) -> TreeNode {
  TreeNode(id: id, label: label, children: [], count: Ok(count))
}

/// Internal node with a right-aligned count.
pub fn node_with_count(
  id: String,
  label: String,
  count: Int,
  children: List(TreeNode),
) -> TreeNode {
  TreeNode(id: id, label: label, children: children, count: Ok(count))
}

/// Attach a count to an existing node.
pub fn with_count(n: TreeNode, count: Int) -> TreeNode {
  TreeNode(..n, count: Ok(count))
}

// ─────────────────────────────────────────────────────────────────
// Widget constructors

/// New tree widget. The first root node is selected initially.
pub fn tree_new(roots: List(TreeNode)) -> TreeWidget {
  TreeWidget(
    roots: roots,
    fg: style.Default,
    bg: style.Default,
    highlight_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.reverse(),
    ),
    glyphs: default_glyphs(),
  )
}

pub fn with_glyphs(t: TreeWidget, g: TreeGlyphs) -> TreeWidget {
  TreeWidget(..t, glyphs: g)
}

pub fn with_highlight_style(t: TreeWidget, s: style.Style) -> TreeWidget {
  TreeWidget(..t, highlight_style: s)
}

pub fn with_colors(
  t: TreeWidget,
  fg: style.Color,
  bg: style.Color,
) -> TreeWidget {
  TreeWidget(..t, fg: fg, bg: bg)
}

pub fn with_style(t: TreeWidget, s: style.Style) -> TreeWidget {
  TreeWidget(..t, fg: s.fg, bg: s.bg)
}

// ─────────────────────────────────────────────────────────────────
// State constructors

/// Initial state: first root node selected, all nodes collapsed.
pub fn state_new() -> TreeState {
  TreeState(expanded: [], selected: "")
}

/// Initial state with first root pre-selected.
pub fn state_from_tree(t: TreeWidget) -> TreeState {
  let first_id = case t.roots {
    [n, ..] -> n.id
    [] -> ""
  }
  TreeState(expanded: [], selected: first_id)
}

// ─────────────────────────────────────────────────────────────────
// State queries

/// ID of the currently selected node. `Error(Nil)` if nothing selected.
pub fn selected(state: TreeState) -> Result(String, Nil) {
  case state.selected {
    "" -> Error(Nil)
    id -> Ok(id)
  }
}

/// `True` if the node with the given `id` is expanded.
pub fn is_expanded(state: TreeState, id: String) -> Bool {
  list.contains(state.expanded, id)
}

// ─────────────────────────────────────────────────────────────────
// Expand / collapse

/// Expand a node (show children).
pub fn expand(id: String, state: TreeState) -> TreeState {
  case list.contains(state.expanded, id) {
    True -> state
    False -> TreeState(..state, expanded: [id, ..state.expanded])
  }
}

/// Collapse a node (hide children).
pub fn collapse(id: String, state: TreeState) -> TreeState {
  TreeState(..state, expanded: list.filter(state.expanded, fn(e) { e != id }))
}

/// Toggle expand/collapse on the currently selected node.
pub fn toggle_selected(state: TreeState, t: TreeWidget) -> TreeState {
  case state.selected {
    "" -> state
    id -> {
      let has_children = node_has_children(t.roots, id)
      case has_children {
        False -> state
        True ->
          case is_expanded(state, id) {
            True -> collapse(id, state)
            False -> expand(id, state)
          }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Navigation

/// Move selection to the next visible node.
pub fn select_next(state: TreeState, t: TreeWidget) -> TreeState {
  let visible = flatten_visible(t.roots, state, 0)
  let ids = list.map(visible, fn(row) { row.id })
  case find_next(ids, state.selected) {
    Ok(next_id) -> TreeState(..state, selected: next_id)
    Error(_) -> state
  }
}

/// Move selection to the previous visible node.
pub fn select_prev(state: TreeState, t: TreeWidget) -> TreeState {
  let visible = flatten_visible(t.roots, state, 0)
  let ids = list.map(visible, fn(row) { row.id })
  case find_prev(ids, state.selected) {
    Ok(prev_id) -> TreeState(..state, selected: prev_id)
    Error(_) -> state
  }
}

/// Number of visible rows (respects expand/collapse state).
/// Use as `total` when building a scrollbar.
pub fn visible_row_count(state: TreeState, t: TreeWidget) -> Int {
  list.length(flatten_visible(t.roots, state, 0))
}

/// Effective scroll offset for a viewport of `height` rows.
/// Use as `offset` when building a scrollbar.
pub fn effective_offset(state: TreeState, t: TreeWidget, height: Int) -> Int {
  case height <= 0 {
    True -> 0
    False -> {
      let rows = flatten_visible(t.roots, state, 0)
      visible_scroll(rows, state.selected, height)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the tree, scrolling so the selected node is visible.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  t: TreeWidget,
  state: TreeState,
) -> buffer.Buffer {
  case area.size.height <= 0 || area.size.width <= 0 {
    True -> buf
    False -> {
      let rows = flatten_visible(t.roots, state, 0)
      let scroll = visible_scroll(rows, state.selected, area.size.height)
      render_rows(buf, area, t, state, rows, scroll, 0)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal: flatten visible nodes into rows

type VisibleRow {
  VisibleRow(
    id: String,
    depth: Int,
    label: String,
    has_children: Bool,
    count: Result(Int, Nil),
  )
}

fn flatten_visible(
  nodes: List(TreeNode),
  state: TreeState,
  depth: Int,
) -> List(VisibleRow) {
  list.flat_map(nodes, fn(n) {
    let has_ch = !list.is_empty(n.children)
    let row =
      VisibleRow(
        id: n.id,
        depth: depth,
        label: n.label,
        has_children: has_ch,
        count: n.count,
      )
    let child_rows = case has_ch && is_expanded(state, n.id) {
      True -> flatten_visible(n.children, state, depth + 1)
      False -> []
    }
    [row, ..child_rows]
  })
}

fn render_rows(
  buf: buffer.Buffer,
  area: geometry.Rect,
  t: TreeWidget,
  state: TreeState,
  rows: List(VisibleRow),
  scroll: Int,
  row_offset: Int,
) -> buffer.Buffer {
  case row_offset >= area.size.height {
    True -> buf
    False -> {
      let visible_idx = scroll + row_offset
      case list.drop(rows, visible_idx) {
        [] -> buf
        [row, ..] -> {
          let y = area.position.y + row_offset
          let is_sel = row.id == state.selected
          let prefix =
            repeat_string(t.glyphs.indent, row.depth)
            <> case row.has_children {
              True ->
                case is_expanded(state, row.id) {
                  True -> t.glyphs.expanded
                  False -> t.glyphs.collapsed
                }
              False -> t.glyphs.leaf
            }
          let count_str = case row.count {
            Ok(n) -> int.to_string(n)
            Error(_) -> ""
          }
          let count_w = text.cell_width(count_str)
          let label_budget = case count_w {
            0 -> area.size.width
            _ -> int.max(0, area.size.width - count_w - 1)
          }
          let label_raw = prefix <> row.label
          let label_part = text.truncate(label_raw, label_budget, "")
          let label_padded = text.pad_right(label_part, label_budget)
          let padded = case count_w {
            0 -> text.pad_right(label_padded, area.size.width)
            _ -> label_padded <> " " <> count_str
          }
          let truncated = text.truncate(padded, area.size.width, "")
          let padded = text.pad_right(truncated, area.size.width)
          let #(fg, bg, modifier) = case is_sel {
            True -> #(
              t.highlight_style.fg,
              t.highlight_style.bg,
              t.highlight_style.modifier,
            )
            False -> #(t.fg, t.bg, style.none())
          }
          let buf2 =
            buffer.set_string(
              buf,
              geometry.Position(x: area.position.x, y: y),
              padded,
              fg,
              bg,
              modifier,
            )
          render_rows(buf2, area, t, state, rows, scroll, row_offset + 1)
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

fn node_has_children(nodes: List(TreeNode), target_id: String) -> Bool {
  case nodes {
    [] -> False
    [n, ..rest] ->
      case n.id == target_id {
        True -> !list.is_empty(n.children)
        False ->
          node_has_children(n.children, target_id)
          || node_has_children(rest, target_id)
      }
  }
}

fn find_next(ids: List(String), current: String) -> Result(String, Nil) {
  case ids {
    [] -> Error(Nil)
    [_] -> Error(Nil)
    [h, next, ..rest] ->
      case h == current {
        True -> Ok(next)
        False -> find_next([next, ..rest], current)
      }
  }
}

fn find_prev(ids: List(String), current: String) -> Result(String, Nil) {
  find_prev_loop(ids, current, Error(Nil))
}

fn find_prev_loop(
  ids: List(String),
  current: String,
  prev: Result(String, Nil),
) -> Result(String, Nil) {
  case ids {
    [] -> Error(Nil)
    [h, ..rest] ->
      case h == current {
        True -> prev
        False -> find_prev_loop(rest, current, Ok(h))
      }
  }
}

fn visible_scroll(
  rows: List(VisibleRow),
  selected: String,
  height: Int,
) -> Int {
  let idx = find_row_index(rows, selected, 0)
  case idx < height {
    True -> 0
    False -> idx - height + 1
  }
}

fn find_row_index(rows: List(VisibleRow), id: String, acc: Int) -> Int {
  case rows {
    [] -> 0
    [r, ..rest] ->
      case r.id == id {
        True -> acc
        False -> find_row_index(rest, id, acc + 1)
      }
  }
}

fn repeat_string(s: String, n: Int) -> String {
  repeat_string_loop(s, n, "")
}

fn repeat_string_loop(s: String, n: Int, acc: String) -> String {
  case n <= 0 {
    True -> acc
    False -> repeat_string_loop(s, n - 1, acc <> s)
  }
}
