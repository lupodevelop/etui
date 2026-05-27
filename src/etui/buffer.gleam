/// Terminal buffer: grid of styled cells + diffing.
/// Dense storage: flat array indexed by `(y - y0) * width + (x - x0)`.
/// Get/set are O(log10 N) on Erlang (array trie), which beats a dict for the
/// integer-keyed, fully-populated buffers that TUI rendering produces.
/// Wide graphemes (CJK, emoji) occupy one Cell + a Continuation marker.
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/list
import gleam/string

// ─────────────────────────────────────────────────────────────────
// External array type (Erlang array / JS flat array)

pub type CellArray

@external(erlang, "etui_buffer_array_ffi", "new")
@external(javascript, "../etui_buffer_array_ffi.mjs", "make")
fn array_new(size: Int, default: Cell) -> CellArray

@external(erlang, "etui_buffer_array_ffi", "get")
@external(javascript, "../etui_buffer_array_ffi.mjs", "get")
fn array_get(index: Int, arr: CellArray) -> Cell

@external(erlang, "etui_buffer_array_ffi", "set")
@external(javascript, "../etui_buffer_array_ffi.mjs", "set")
fn array_set(index: Int, value: Cell, arr: CellArray) -> CellArray

/// Bulk-fill all Width×Height cells from a single row text using array:from_list.
/// Erlang only, JS falls back to the Gleam body (repeated fill_graphemes).
/// Faster than fill_string called per-row because the trie is built once.
@external(erlang, "etui_buffer_array_ffi", "fill_all_rows")
fn fill_all_rows_ffi(
  width: Int,
  height: Int,
  str: String,
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
  link: String,
  default: Cell,
) -> CellArray {
  let size = int.max(width * height, 0)
  fill_all_rows_gleam(
    array_new(size, default),
    0,
    height,
    width,
    str,
    fg,
    bg,
    modifier,
    link,
  )
}

fn fill_all_rows_gleam(
  arr: CellArray,
  row: Int,
  height: Int,
  width: Int,
  str: String,
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
  link: String,
) -> CellArray {
  case row >= height {
    True -> arr
    False -> {
      let start = row * width
      let arr2 =
        fill_graphemes(
          arr,
          start,
          start + width,
          string.to_graphemes(str),
          fg,
          bg,
          modifier,
          link,
        )
      fill_all_rows_gleam(
        arr2,
        row + 1,
        height,
        width,
        str,
        fg,
        bg,
        modifier,
        link,
      )
    }
  }
}

/// Fill cells from a string into the array, capped at max_idx (end of row).
/// Erlang: processes binary directly, no Gleam list/fold overhead.
/// Other targets: Gleam fallback using grapheme fold.
@external(erlang, "etui_buffer_array_ffi", "fill_string")
fn fill_string_ffi(
  arr: CellArray,
  start_idx: Int,
  max_idx: Int,
  str: String,
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
  link: String,
) -> CellArray {
  fill_graphemes(
    arr,
    start_idx,
    max_idx,
    string.to_graphemes(str),
    fg,
    bg,
    modifier,
    link,
  )
}

fn fill_graphemes(
  arr: CellArray,
  idx: Int,
  max_idx: Int,
  gs: List(String),
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
  link: String,
) -> CellArray {
  case idx >= max_idx {
    True -> arr
    False ->
      case gs {
        [] -> arr
        [g, ..rest] -> {
          let w = text.grapheme_cell_width(g)
          let cell =
            Cell(
              content: Content(symbol: g, width: w),
              fg: fg,
              bg: bg,
              modifier: modifier,
              link: link,
            )
          let arr2 = array_set(idx, cell, arr)
          case w >= 2 {
            True -> {
              let arr3 = case idx + 1 < max_idx {
                True ->
                  array_set(idx + 1, continuation_cell(fg, bg, modifier), arr2)
                False -> arr2
              }
              fill_graphemes(
                arr3,
                idx + 2,
                max_idx,
                rest,
                fg,
                bg,
                modifier,
                link,
              )
            }
            False ->
              fill_graphemes(
                arr2,
                idx + 1,
                max_idx,
                rest,
                fg,
                bg,
                modifier,
                link,
              )
          }
        }
      }
  }
}

// ─────────────────────────────────────────────────────────────────
// Types

/// Content variant for a terminal cell.
pub type CellContent {
  /// A normal or wide grapheme. `width` = 1 or 2.
  Content(symbol: String, width: Int)
  /// Marker for the second cell of a wide grapheme. Never drawn directly.
  Continuation
}

/// One cell in the terminal grid: a grapheme + colors + modifiers + optional hyperlink.
pub type Cell {
  Cell(
    content: CellContent,
    fg: style.Color,
    bg: style.Color,
    modifier: style.Modifier,
    /// OSC 8 hyperlink URI. Empty string = no link. Emitted on render.
    link: String,
  )
}

pub opaque type Buffer {
  Buffer(area: geometry.Rect, cells: CellArray)
}

/// A diff operation: move cursor to `position`, write a run of `cells`.
pub type BufferOp {
  Patch(position: geometry.Position, cells: List(Cell))
}

// ─────────────────────────────────────────────────────────────────
// Accessors

/// The rect this buffer covers.
pub fn area(buf: Buffer) -> geometry.Rect {
  buf.area
}

/// Width in cells.
pub fn width(buf: Buffer) -> Int {
  buf.area.size.width
}

/// Height in rows.
pub fn height(buf: Buffer) -> Int {
  buf.area.size.height
}

/// Symbol string of a cell. Returns " " for Continuation cells.
pub fn cell_symbol(cell: Cell) -> String {
  case cell.content {
    Content(symbol: s, ..) -> s
    Continuation -> " "
  }
}

/// Foreground color of a cell.
pub fn cell_fg(cell: Cell) -> style.Color {
  cell.fg
}

/// Background color of a cell.
pub fn cell_bg(cell: Cell) -> style.Color {
  cell.bg
}

/// Text modifier of a cell.
pub fn cell_modifier(cell: Cell) -> style.Modifier {
  cell.modifier
}

/// True if this cell is the second column of a wide grapheme (never rendered directly).
pub fn is_continuation(cell: Cell) -> Bool {
  case cell.content {
    Continuation -> True
    _ -> False
  }
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// Empty cell (space, default style, no link).
pub fn empty_cell() -> Cell {
  Cell(
    content: Content(symbol: " ", width: 1),
    fg: style.Default,
    bg: style.Default,
    modifier: style.none(),
    link: "",
  )
}

/// Continuation cell (second column of a wide grapheme).
pub fn continuation_cell(
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
) -> Cell {
  Cell(content: Continuation, fg: fg, bg: bg, modifier: modifier, link: "")
}

/// Accessor: OSC 8 hyperlink URI of a cell (empty = no link).
pub fn cell_link(cell: Cell) -> String {
  cell.link
}

/// New buffer with given area. All cells start as `empty_cell()`.
pub fn buffer_new(area: geometry.Rect) -> Buffer {
  let size = int.max(area.size.width * area.size.height, 0)
  Buffer(area: area, cells: array_new(size, empty_cell()))
}

/// Create a buffer with every row pre-filled with `row_text`.
/// Uses bulk array construction: one pass instead of `buffer_new` followed by
/// a `set_string` for every row.
pub fn buffer_new_filled(
  area: geometry.Rect,
  row_text: String,
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
) -> Buffer {
  let default = empty_cell()
  Buffer(
    area: area,
    cells: fill_all_rows_ffi(
      area.size.width,
      area.size.height,
      row_text,
      fg,
      bg,
      modifier,
      "",
      default,
    ),
  )
}

// ─────────────────────────────────────────────────────────────────
// Index helpers

fn pos_to_idx(area: geometry.Rect, pos: geometry.Position) -> Int {
  { pos.y - area.position.y } * area.size.width + { pos.x - area.position.x }
}

// ─────────────────────────────────────────────────────────────────
// Cell operations

/// Get cell at position. Returns empty_cell() for out-of-bounds.
pub fn get_cell(buffer: Buffer, pos: geometry.Position) -> Cell {
  case geometry.contains(buffer.area, pos) {
    False -> empty_cell()
    True -> array_get(pos_to_idx(buffer.area, pos), buffer.cells)
  }
}

/// Set cell at position. Out-of-bounds writes are ignored.
pub fn set_cell(buffer: Buffer, pos: geometry.Position, cell: Cell) -> Buffer {
  case geometry.contains(buffer.area, pos) {
    True ->
      Buffer(
        ..buffer,
        cells: array_set(pos_to_idx(buffer.area, pos), cell, buffer.cells),
      )
    False -> buffer
  }
}

/// Set cells from a string starting at `pos`. No hyperlink.
/// Wide graphemes (width=2) take one Cell + one Continuation cell.
pub fn set_string(
  buffer: Buffer,
  pos: geometry.Position,
  str: String,
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
) -> Buffer {
  set_string_linked(buffer, pos, str, fg, bg, modifier, "")
}

/// Set cells from a string with an OSC 8 hyperlink URI.
/// Pass `""` for no link (same as `set_string`).
pub fn set_string_linked(
  buffer: Buffer,
  pos: geometry.Position,
  str: String,
  fg: style.Color,
  bg: style.Color,
  modifier: style.Modifier,
  link: String,
) -> Buffer {
  case geometry.contains(buffer.area, pos) {
    False -> buffer
    True -> {
      let start_idx = pos_to_idx(buffer.area, pos)
      // Cap at end of row, strings never wrap to the next row
      let row_end =
        { pos.y - buffer.area.position.y + 1 } * buffer.area.size.width
      Buffer(
        ..buffer,
        cells: fill_string_ffi(
          buffer.cells,
          start_idx,
          row_end,
          str,
          fg,
          bg,
          modifier,
          link,
        ),
      )
    }
  }
}

/// Clear all cells in a rect (reset to empty_cell).
pub fn clear(buffer: Buffer, rect: geometry.Rect) -> Buffer {
  let y_max = geometry.bottom(rect)
  let x_max = geometry.right(rect)
  clear_rows(buffer, rect.position.y, y_max, rect.position.x, x_max)
}

fn clear_rows(
  buf: Buffer,
  y: Int,
  y_max: Int,
  x_min: Int,
  x_max: Int,
) -> Buffer {
  case y >= y_max {
    True -> buf
    False ->
      clear_rows(clear_row(buf, y, x_min, x_max), y + 1, y_max, x_min, x_max)
  }
}

fn clear_row(buf: Buffer, y: Int, x: Int, x_max: Int) -> Buffer {
  case x >= x_max {
    True -> buf
    False -> {
      let pos = geometry.Position(x: x, y: y)
      let cells = case geometry.contains(buf.area, pos) {
        True -> array_set(pos_to_idx(buf.area, pos), empty_cell(), buf.cells)
        False -> buf.cells
      }
      clear_row(Buffer(..buf, cells: cells), y, x + 1, x_max)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Diffing

// Pre-extracted buffer view, avoids repeated record field accesses and
// geometry.contains checks in the diff and to_ansi inner loops.
type BufView {
  BufView(
    cells: CellArray,
    y0: Int,
    x0: Int,
    width: Int,
    height: Int,
    size: Int,
  )
}

fn buf_view(buf: Buffer) -> BufView {
  BufView(
    cells: buf.cells,
    y0: buf.area.position.y,
    x0: buf.area.position.x,
    width: buf.area.size.width,
    height: buf.area.size.height,
    size: buf.area.size.width * buf.area.size.height,
  )
}

// O(1) cell fetch with cheap bounds guard, no geometry.contains overhead.
fn bv_cell_at(bv: BufView, row_base: Int, x: Int) -> Cell {
  let idx = row_base + x - bv.x0
  case idx >= 0 && idx < bv.size {
    True -> array_get(idx, bv.cells)
    False -> empty_cell()
  }
}

/// Compute minimal diff between two buffers as a list of patches.
pub fn diff(prev: Buffer, next: Buffer) -> List(BufferOp) {
  let y_min = min_int(prev.area.position.y, next.area.position.y)
  let y_max = max_int(geometry.bottom(prev.area), geometry.bottom(next.area))
  let x_min = min_int(prev.area.position.x, next.area.position.x)
  let x_max = max_int(geometry.right(prev.area), geometry.right(next.area))
  diff_rows(buf_view(prev), buf_view(next), y_min, y_max, x_min, x_max, [])
}

fn diff_rows(
  prev: BufView,
  next: BufView,
  y: Int,
  y_max: Int,
  x_min: Int,
  x_max: Int,
  rev_acc: List(BufferOp),
) -> List(BufferOp) {
  case y >= y_max {
    True -> list.reverse(rev_acc)
    False -> {
      let prev_rb = { y - prev.y0 } * prev.width
      let next_rb = { y - next.y0 } * next.width
      let rev_acc2 =
        diff_row(prev, next, prev_rb, next_rb, y, x_min, x_max, rev_acc)
      diff_rows(prev, next, y + 1, y_max, x_min, x_max, rev_acc2)
    }
  }
}

fn diff_row(
  prev: BufView,
  next: BufView,
  prev_rb: Int,
  next_rb: Int,
  y: Int,
  x: Int,
  x_max: Int,
  rev_acc: List(BufferOp),
) -> List(BufferOp) {
  case x >= x_max {
    True -> rev_acc
    False -> {
      let prev_cell = bv_cell_at(prev, prev_rb, x)
      let next_cell = bv_cell_at(next, next_rb, x)
      case cells_equal(prev_cell, next_cell) {
        True -> diff_row(prev, next, prev_rb, next_rb, y, x + 1, x_max, rev_acc)
        False -> {
          let pos = geometry.Position(x: x, y: y)
          let #(run, next_x) =
            collect_run(prev, next, prev_rb, next_rb, x, x_max, [])
          diff_row(prev, next, prev_rb, next_rb, y, next_x, x_max, [
            Patch(pos, run),
            ..rev_acc
          ])
        }
      }
    }
  }
}

fn collect_run(
  prev: BufView,
  next: BufView,
  prev_rb: Int,
  next_rb: Int,
  x: Int,
  x_max: Int,
  run: List(Cell),
) -> #(List(Cell), Int) {
  case x >= x_max {
    True -> #(list.reverse(run), x)
    False -> {
      let prev_cell = bv_cell_at(prev, prev_rb, x)
      let next_cell = bv_cell_at(next, next_rb, x)
      case cells_equal(prev_cell, next_cell) {
        True -> #(list.reverse(run), x)
        False ->
          collect_run(prev, next, prev_rb, next_rb, x + 1, x_max, [
            next_cell,
            ..run
          ])
      }
    }
  }
}

// Structural `==` compares every field in one BEAM term-comparison BIF,
// faster than a hand-rolled check in the per-cell diff loop.
fn cells_equal(a: Cell, b: Cell) -> Bool {
  a == b
}

// ─────────────────────────────────────────────────────────────────
// ANSI rendering

// ─── Style-run tracking ──────────────────────────────────────────
// Tracks the currently applied ANSI style to avoid re-emitting unchanged
// sequences across consecutive cells. The terminal preserves style across
// cursor moves, so we can thread this state across rows and patches.

type RunStyle {
  RunStyle(
    fg: style.Color,
    bg: style.Color,
    modifier: style.Modifier,
    link: String,
  )
}

fn blank_run_style() -> RunStyle {
  RunStyle(
    fg: style.Default,
    bg: style.Default,
    modifier: style.none(),
    link: "",
  )
}

fn run_style_active(rs: RunStyle) -> Bool {
  style.ansi_fg(rs.fg) != ""
  || style.ansi_bg(rs.bg) != ""
  || style.ansi_modifier(rs.modifier) != ""
  || rs.link != ""
}

// Emit a cell relative to the current RunStyle.
// When style is unchanged: emit only the text. When it changes: emit
// the minimal transition (link-close, reset, new style, link-open) then text.
fn emit_cell(rs: RunStyle, cell: Cell) -> #(String, RunStyle) {
  case is_continuation(cell) {
    True -> #("", rs)
    False -> {
      let same =
        cell.fg == rs.fg
        && cell.bg == rs.bg
        && cell.modifier == rs.modifier
        && cell.link == rs.link
      case same {
        True -> #(cell_symbol(cell), rs)
        False -> {
          let link_close = case rs.link {
            "" -> ""
            _ -> osc8_close()
          }
          let reset_seq = case run_style_active(rs) {
            True -> style.ansi_reset()
            False -> ""
          }
          let fg_seq = style.ansi_fg(cell.fg)
          let bg_seq = style.ansi_bg(cell.bg)
          let mod_seq = style.ansi_modifier(cell.modifier)
          let link_open = case cell.link {
            "" -> ""
            uri -> osc8_open(uri)
          }
          let new_rs =
            RunStyle(
              fg: cell.fg,
              bg: cell.bg,
              modifier: cell.modifier,
              link: cell.link,
            )
          #(
            link_close
              <> reset_seq
              <> fg_seq
              <> bg_seq
              <> mod_seq
              <> link_open
              <> cell_symbol(cell),
            new_rs,
          )
        }
      }
    }
  }
}

/// Full-buffer render to an ANSI string.
/// Emits a MoveCursor for every row, then each cell with style transitions
/// only when the style actually changes between adjacent cells.
/// Use for the first frame or after a terminal resize.
pub fn to_ansi(buf: Buffer) -> String {
  let #(output, final_rs) =
    to_ansi_rows(buf_view(buf), 0, blank_run_style(), "")
  let trailing = case run_style_active(final_rs) {
    True -> style.ansi_reset()
    False -> ""
  }
  output <> trailing
}

fn to_ansi_rows(
  bv: BufView,
  row: Int,
  rs: RunStyle,
  acc: String,
) -> #(String, RunStyle) {
  case row >= bv.height {
    True -> #(acc, rs)
    False -> {
      let move = move_cursor_seq(bv.x0, bv.y0 + row)
      let #(row_str, new_rs) = to_ansi_row(bv, row * bv.width, 0, rs, "")
      to_ansi_rows(bv, row + 1, new_rs, acc <> move <> row_str)
    }
  }
}

fn to_ansi_row(
  bv: BufView,
  row_base: Int,
  col: Int,
  rs: RunStyle,
  acc: String,
) -> #(String, RunStyle) {
  case col >= bv.width {
    True -> #(acc, rs)
    False -> {
      let cell = bv_cell_at(bv, row_base, bv.x0 + col)
      let #(s, new_rs) = emit_cell(rs, cell)
      to_ansi_row(bv, row_base, col + 1, new_rs, acc <> s)
    }
  }
}

/// Convert a list of `BufferOp` patches to an ANSI string.
/// Each patch moves the cursor once, then writes a run of cells.
/// Style is tracked across the entire patch list, cursor moves do not
/// reset terminal style, so we avoid redundant escape sequences.
/// Cheaper than `to_ansi` when only a small fraction of cells changed.
pub fn patches_to_ansi(ops: List(BufferOp)) -> String {
  case ops {
    [] -> ""
    _ -> {
      let #(output, final_rs) =
        list.fold(ops, #("", blank_run_style()), fn(acc, op) {
          let #(str, rs) = acc
          let move = move_cursor_seq(op.position.x, op.position.y)
          let #(cells_str, new_rs) =
            list.fold(op.cells, #("", rs), fn(c_acc, cell) {
              let #(c_str, c_rs) = c_acc
              let #(s, next_rs) = emit_cell(c_rs, cell)
              #(c_str <> s, next_rs)
            })
          #(str <> move <> cells_str, new_rs)
        })
      let trailing = case run_style_active(final_rs) {
        True -> style.ansi_reset()
        False -> ""
      }
      output <> trailing
    }
  }
}

/// Diff `prev` against `curr` and return the minimal ANSI to bring the
/// terminal from `prev`'s state to `curr`'s state.
/// On the first frame (or after resize) pass an empty buffer as `prev`.
pub fn diff_to_ansi(prev: Buffer, curr: Buffer) -> String {
  patches_to_ansi(diff(prev, curr))
}

// OSC 8 hyperlink sequences (supported by iTerm2, Kitty, VTE, Windows Terminal).
fn osc8_open(uri: String) -> String {
  "\u{001B}]8;;" <> uri <> "\u{001B}\\"
}

fn osc8_close() -> String {
  "\u{001B}]8;;\u{001B}\\"
}

fn move_cursor_seq(x: Int, y: Int) -> String {
  "\u{001B}[" <> int.to_string(y + 1) <> ";" <> int.to_string(x + 1) <> "H"
}

// ─────────────────────────────────────────────────────────────────
// Helpers

fn min_int(a: Int, b: Int) -> Int {
  case a < b {
    True -> a
    False -> b
  }
}

fn max_int(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
  }
}
