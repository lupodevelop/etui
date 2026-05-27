/// Table widget: scrollable grid of rows and columns with optional selection.
///
/// Columns are separated by `│`. Each column is padded/truncated to its width.
/// The first row is optionally treated as a header (rendered with reverse style
/// when `show_header` is true). Use `render_stateful` to track selection.
///
/// Example:
/// ```gleam
/// table_new([["Alice", "30"], ["Bob", "25"]])
/// |> with_col_widths([12, 5])
/// |> table.render(buf, area)
/// ```
import etui/anim
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/list as glist

// ─────────────────────────────────────────────────────────────────
// Types

/// Table widget configuration. `col_widths` are in terminal cells.
pub type TableWidget {
  TableWidget(
    rows: List(List(String)),
    /// Fixed column widths in cells. Used when `col_constraints` is empty.
    col_widths: List(Int),
    /// Constraint-based column widths. When non-empty, resolved at render time
    /// from the available area width (separators subtracted automatically).
    col_constraints: List(geometry.Constraint),
    show_header: Bool,
    fg: style.Color,
    bg: style.Color,
    highlight_style: style.Style,
    /// Blink period in frames (0 = no blink).
    blink_period: Int,
  )
}

/// Scroll and selection state. Keep external so state persists across renders.
pub type TableState {
  TableState(selected_row: Int, offset: Int)
}

// ─────────────────────────────────────────────────────────────────
// Widget config constructors

/// New table. Column widths default to 10 cells each.
pub fn table_new(rows: List(List(String))) -> TableWidget {
  let col_widths = case rows {
    [] -> []
    [first, ..] -> glist.repeat(10, glist.length(first))
  }
  TableWidget(
    rows: rows,
    col_widths: col_widths,
    col_constraints: [],
    show_header: False,
    fg: style.Default,
    bg: style.Default,
    highlight_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.reverse(),
    ),
    blink_period: 0,
  )
}

/// Override column widths (cell counts). Must match number of columns.
pub fn with_col_widths(t: TableWidget, widths: List(Int)) -> TableWidget {
  TableWidget(..t, col_widths: widths)
}

/// Constraint-based column widths, resolved from area width at render time.
/// When set, takes precedence over `col_widths`.
/// Separator cells (│) are subtracted before resolving.
pub fn with_col_constraints(
  t: TableWidget,
  constraints: List(geometry.Constraint),
) -> TableWidget {
  TableWidget(..t, col_constraints: constraints)
}

/// When true, `t.rows[0]` is rendered as a bold header row (never selectable).
/// `selected_row` uses absolute indices: 0 = header, 1 = first data row, etc.
/// Initialize state with `select_row(state_new(), 1)` for the first data row.
pub fn with_header(t: TableWidget, show: Bool) -> TableWidget {
  TableWidget(..t, show_header: show)
}

pub fn with_colors(
  t: TableWidget,
  fg: style.Color,
  bg: style.Color,
) -> TableWidget {
  TableWidget(..t, fg: fg, bg: bg)
}

pub fn with_highlight_style(t: TableWidget, s: style.Style) -> TableWidget {
  TableWidget(..t, highlight_style: s)
}

pub fn with_style(t: TableWidget, s: style.Style) -> TableWidget {
  TableWidget(..t, fg: s.fg, bg: s.bg)
}

/// Blink period in frames. 0 = steady (no blink). Use with `render_animated`.
pub fn with_blink(t: TableWidget, period: Int) -> TableWidget {
  TableWidget(..t, blink_period: period)
}

// ─────────────────────────────────────────────────────────────────
// State constructors and navigation

/// Initial state: selected_row=0, no scroll offset.
/// When using `with_header(True)`, row 0 is the header (not selectable).
/// Use `select_row(state_new(), 1)` to start with the first data row highlighted.
pub fn state_new() -> TableState {
  TableState(selected_row: 0, offset: 0)
}

/// Jump to a specific row (clamped to ≥ 0).
pub fn select_row(state: TableState, idx: Int) -> TableState {
  TableState(..state, selected_row: int.max(0, idx))
}

/// Move selection down by one, clamped to last row.
pub fn select_next_row(state: TableState, row_count: Int) -> TableState {
  let max_idx = int.max(0, row_count - 1)
  TableState(..state, selected_row: int.min(max_idx, state.selected_row + 1))
}

/// Move selection up by one, clamped to 0.
pub fn select_prev_row(state: TableState) -> TableState {
  TableState(..state, selected_row: int.max(0, state.selected_row - 1))
}

/// Clamp `selected_row` to `[0, row_count - 1]`.
/// Call after replacing the row list to avoid a stale selection index.
pub fn clamp_state(state: TableState, row_count: Int) -> TableState {
  let max = int.max(0, row_count - 1)
  TableState(..state, selected_row: int.min(state.selected_row, max))
}

/// Effective scroll offset for a viewport of `visible_data_h` data rows.
/// When `show_header` is True, pass `area.size.height - 1`; otherwise pass `area.size.height`.
/// Pass as `offset` to `scrollbar.scrollbar_new`.
pub fn effective_offset(state: TableState, visible_data_h: Int) -> Int {
  scroll_offset(state.selected_row, state.offset, visible_data_h)
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render without selection highlight.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  t: TableWidget,
) -> buffer.Buffer {
  case area.size.height <= 0 {
    True -> buf
    False -> do_render(buf, area, t, -1, 0, 0)
  }
}

/// Render with selection and auto-scrolling from state.
pub fn render_stateful(
  buf: buffer.Buffer,
  area: geometry.Rect,
  t: TableWidget,
  state: TableState,
) -> buffer.Buffer {
  case area.size.height <= 0 {
    True -> buf
    False -> {
      // With a header row, one cell is reserved at y=0; data scrolls in H-1 rows.
      let visible_data = case t.show_header {
        True -> int.max(0, area.size.height - 1)
        False -> area.size.height
      }
      let offset = scroll_offset(state.selected_row, state.offset, visible_data)
      do_render(buf, area, t, state.selected_row, offset, 0)
    }
  }
}

/// Like `render_stateful` but supports blinking selection via `t.blink_period`.
/// Pass the current `AnimState.frame`; use `with_blink(t, period)` to configure.
pub fn render_animated(
  buf: buffer.Buffer,
  area: geometry.Rect,
  t: TableWidget,
  state: TableState,
  frame: Int,
) -> buffer.Buffer {
  case area.size.height <= 0 {
    True -> buf
    False -> {
      let visible_data = case t.show_header {
        True -> int.max(0, area.size.height - 1)
        False -> area.size.height
      }
      let offset = scroll_offset(state.selected_row, state.offset, visible_data)
      let show = anim.blink(frame, t.blink_period)
      let sel = case show {
        True -> state.selected_row
        False -> -1
      }
      do_render(buf, area, t, sel, offset, 0)
    }
  }
}

fn do_render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  t: TableWidget,
  selected: Int,
  offset: Int,
  y_offset: Int,
) -> buffer.Buffer {
  let col_widths = case t.col_constraints {
    [] -> t.col_widths
    constraints -> {
      geometry.resolve_sizes(area.size.width, constraints)
    }
  }
  case y_offset >= area.size.height {
    True -> buf
    False -> {
      let y = area.position.y + y_offset
      // When show_header is True, y_offset=0 renders the header row (rows[0])
      // with bold style. Data rows follow at y_offset=1..H-1, and their absolute
      // index in t.rows is offset+y_offset (which equals 1+offset+data_i since
      // y_offset starts at 1 for the first data row).
      let is_header = t.show_header && y_offset == 0
      let row_idx = offset + y_offset
      let is_selected = !is_header && row_idx == selected
      let row_line = case is_header {
        True ->
          case get_row_at(t.rows, 0) {
            Ok(row) -> render_row_line(row, col_widths, area.size.width, False)
            Error(_) -> render_empty_line(area.size.width)
          }
        False ->
          case get_row_at(t.rows, row_idx) {
            Ok(row) ->
              render_row_line(row, col_widths, area.size.width, is_selected)
            Error(_) -> render_empty_line(area.size.width)
          }
      }
      let #(row_fg, row_bg, row_modifier) = case is_header {
        True -> #(t.fg, t.bg, style.bold())
        False ->
          case is_selected {
            True -> #(
              t.highlight_style.fg,
              t.highlight_style.bg,
              t.highlight_style.modifier,
            )
            False -> #(t.fg, t.bg, style.none())
          }
      }
      let buf_new =
        buffer.set_string(
          buf,
          geometry.Position(x: area.position.x, y: y),
          row_line,
          row_fg,
          row_bg,
          row_modifier,
        )
      do_render(buf_new, area, t, selected, offset, y_offset + 1)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Scroll helpers

fn scroll_offset(selected: Int, offset: Int, height: Int) -> Int {
  case selected < offset {
    True -> selected
    False ->
      case height <= 0 {
        True -> offset
        False ->
          case selected >= offset + height {
            True -> selected - height + 1
            False -> offset
          }
      }
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

fn get_row_at(rows: List(List(String)), idx: Int) -> Result(List(String), Nil) {
  case idx {
    i if i < 0 -> Error(Nil)
    0 ->
      case rows {
        [h, ..] -> Ok(h)
        [] -> Error(Nil)
      }
    _ -> get_row_at(glist.drop(rows, 1), idx - 1)
  }
}

fn render_row_line(
  row: List(String),
  col_widths: List(Int),
  max_width: Int,
  is_selected: Bool,
) -> String {
  let cells = render_cells(row, col_widths)
  let line =
    glist.fold(cells, "", fn(acc, cell) {
      case acc {
        "" -> cell
        _ -> acc <> "│" <> cell
      }
    })
  let prefix = case is_selected {
    True -> "▶"
    False -> " "
  }
  text.truncate(prefix <> line, max_width, "")
  |> text.pad_right(max_width)
}

fn render_cells(row: List(String), widths: List(Int)) -> List(String) {
  case row, widths {
    _, [] -> []
    [], [width, ..rest_widths] -> {
      // Row has fewer cells than columns: pad with empty cells.
      let formatted = text.pad_right("", int.max(0, width - 1))
      [formatted, ..render_cells([], rest_widths)]
    }
    [cell, ..rest_row], [width, ..rest_widths] -> {
      let formatted =
        text.truncate(cell, width - 1, "")
        |> text.pad_right(width - 1)
      [formatted, ..render_cells(rest_row, rest_widths)]
    }
  }
}

fn render_empty_line(width: Int) -> String {
  text.pad_right("", width)
}
