/// Multi-select list. Each item can be toggled on or off independently.
/// The cursor moves through the list; your update function calls `toggle`
/// to flip the cursor item. `max` caps the total selected (0 = unlimited).
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/list
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

pub type MultiSelectWidget {
  MultiSelectWidget(
    items: List(String),
    cursor_style: style.Style,
    selected_style: style.Style,
    checked_mark: String,
    unchecked_mark: String,
    cursor_mark: String,
    max: Int,
    fg: style.Color,
    bg: style.Color,
  )
}

/// `selected` is kept sorted ascending and contains unique indices.
pub type MultiSelectState {
  MultiSelectState(cursor: Int, selected: List(Int), offset: Int)
}

// ─────────────────────────────────────────────────────────────────
// Widget config constructors

pub fn multi_select_new(items: List(String)) -> MultiSelectWidget {
  MultiSelectWidget(
    items: items,
    cursor_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.reverse(),
    ),
    selected_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.bold(),
    ),
    checked_mark: "[x] ",
    unchecked_mark: "[ ] ",
    cursor_mark: "▶ ",
    max: 0,
    fg: style.Default,
    bg: style.Default,
  )
}

/// Cap the number of selected items. 0 = unlimited.
pub fn with_max(w: MultiSelectWidget, m: Int) -> MultiSelectWidget {
  MultiSelectWidget(..w, max: int.max(0, m))
}

pub fn with_marks(
  w: MultiSelectWidget,
  checked: String,
  unchecked: String,
) -> MultiSelectWidget {
  MultiSelectWidget(..w, checked_mark: checked, unchecked_mark: unchecked)
}

pub fn with_cursor_mark(w: MultiSelectWidget, m: String) -> MultiSelectWidget {
  MultiSelectWidget(..w, cursor_mark: m)
}

pub fn with_cursor_style(
  w: MultiSelectWidget,
  s: style.Style,
) -> MultiSelectWidget {
  MultiSelectWidget(..w, cursor_style: s)
}

pub fn with_selected_style(
  w: MultiSelectWidget,
  s: style.Style,
) -> MultiSelectWidget {
  MultiSelectWidget(..w, selected_style: s)
}

pub fn with_colors(
  w: MultiSelectWidget,
  fg: style.Color,
  bg: style.Color,
) -> MultiSelectWidget {
  MultiSelectWidget(..w, fg: fg, bg: bg)
}

// ─────────────────────────────────────────────────────────────────
// State

pub fn state_new() -> MultiSelectState {
  MultiSelectState(cursor: 0, selected: [], offset: 0)
}

pub fn select_next(
  state: MultiSelectState,
  item_count: Int,
) -> MultiSelectState {
  let max_idx = int.max(0, item_count - 1)
  MultiSelectState(..state, cursor: int.min(state.cursor + 1, max_idx))
}

pub fn select_prev(state: MultiSelectState) -> MultiSelectState {
  MultiSelectState(..state, cursor: int.max(state.cursor - 1, 0))
}

/// Toggle the cursor item. Respects `max` from the widget config.
pub fn toggle(state: MultiSelectState, max: Int) -> MultiSelectState {
  case list.contains(state.selected, state.cursor) {
    True ->
      MultiSelectState(
        ..state,
        selected: list.filter(state.selected, fn(i) { i != state.cursor }),
      )
    False ->
      case max > 0 && list.length(state.selected) >= max {
        True -> state
        False ->
          MultiSelectState(
            ..state,
            selected: insert_sorted(state.selected, state.cursor),
          )
      }
  }
}

pub fn is_selected(state: MultiSelectState, idx: Int) -> Bool {
  list.contains(state.selected, idx)
}

pub fn selected_indices(state: MultiSelectState) -> List(Int) {
  state.selected
}

/// Pull the selected item strings in original order.
pub fn selected_values(
  items: List(String),
  state: MultiSelectState,
) -> List(String) {
  items
  |> list.index_map(fn(item, i) { #(i, item) })
  |> list.filter_map(fn(pair) {
    case list.contains(state.selected, pair.0) {
      True -> Ok(pair.1)
      False -> Error(Nil)
    }
  })
}

pub fn clear_selection(state: MultiSelectState) -> MultiSelectState {
  MultiSelectState(..state, selected: [])
}

/// Effective scroll offset for a viewport of `height` rows.
pub fn effective_offset(state: MultiSelectState, height: Int) -> Int {
  scroll_offset(state.cursor, state.offset, height)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  w: MultiSelectWidget,
  state: MultiSelectState,
) -> buffer.Buffer {
  case area.size.height <= 0 || area.size.width <= 0 {
    True -> buf
    False -> {
      let offset = scroll_offset(state.cursor, state.offset, area.size.height)
      render_rows(buf, area, w, state, offset, 0)
    }
  }
}

fn render_rows(
  buf: buffer.Buffer,
  area: geometry.Rect,
  w: MultiSelectWidget,
  state: MultiSelectState,
  offset: Int,
  row_off: Int,
) -> buffer.Buffer {
  case row_off >= area.size.height {
    True -> buf
    False -> {
      let item_idx = offset + row_off
      case list.drop(w.items, item_idx) {
        [] -> buf
        [item, ..] -> {
          let y = area.position.y + row_off
          let is_cursor = item_idx == state.cursor
          let is_sel = list.contains(state.selected, item_idx)
          let prefix = case is_cursor {
            True -> w.cursor_mark
            False -> string.repeat(" ", text.cell_width(w.cursor_mark))
          }
          let mark = case is_sel {
            True -> w.checked_mark
            False -> w.unchecked_mark
          }
          let raw = prefix <> mark <> item
          let truncated = text.truncate(raw, area.size.width, "")
          let padded = text.pad_right(truncated, area.size.width)
          let #(fg, bg, modifier) = case is_cursor, is_sel {
            True, _ -> #(
              w.cursor_style.fg,
              w.cursor_style.bg,
              w.cursor_style.modifier,
            )
            False, True -> #(
              w.selected_style.fg,
              w.selected_style.bg,
              w.selected_style.modifier,
            )
            False, False -> #(w.fg, w.bg, style.none())
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
          render_rows(buf2, area, w, state, offset, row_off + 1)
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Helpers

fn scroll_offset(cursor: Int, offset: Int, height: Int) -> Int {
  case cursor < offset {
    True -> cursor
    False ->
      case height <= 0 {
        True -> offset
        False ->
          case cursor >= offset + height {
            True -> cursor - height + 1
            False -> offset
          }
      }
  }
}

fn insert_sorted(lst: List(Int), n: Int) -> List(Int) {
  case lst {
    [] -> [n]
    [h, ..] if n < h -> [n, ..lst]
    [h, ..] if n == h -> lst
    [h, ..t] -> [h, ..insert_sorted(t, n)]
  }
}
