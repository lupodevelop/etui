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

/// A run of writes.
///
/// The JavaScript store has to copy the cell array to keep an old buffer
/// intact, so writing a cell at a time makes filling a buffer quadratic in its
/// size: a 200x50 fill cost about 35 ms, more than a whole 60 fps frame. A
/// draft copies once and writes many times. Erlang's array is a persistent
/// trie already, so there a draft is the array itself.
///
/// A draft must not escape the loop that made it. Every use below takes one,
/// writes, and commits within a single function.
pub type Draft

@external(erlang, "etui_buffer_array_ffi", "draft")
@external(javascript, "../etui_buffer_array_ffi.mjs", "draft")
fn draft(arr: CellArray) -> Draft

@external(erlang, "etui_buffer_array_ffi", "draft_set")
@external(javascript, "../etui_buffer_array_ffi.mjs", "draftSet")
fn draft_set(index: Int, value: Cell, d: Draft) -> Draft

@external(erlang, "etui_buffer_array_ffi", "draft_get")
@external(javascript, "../etui_buffer_array_ffi.mjs", "draftGet")
fn draft_get(index: Int, d: Draft) -> Cell

@external(erlang, "etui_buffer_array_ffi", "commit")
@external(javascript, "../etui_buffer_array_ffi.mjs", "commit")
fn commit(d: Draft) -> CellArray

/// Bulk-fill all Width×Height cells from a single row text using array:from_list.
/// Erlang only, JS falls back to the Gleam body (repeated fill_graphemes).
/// Faster than fill_string called per-row because the trie is built once.
@external(erlang, "etui_buffer_array_ffi", "fill_all_rows")
fn fill_all_rows_ffi(
  width: Int,
  height: Int,
  str: String,
  s: style.Style,
  link: String,
  default: Cell,
) -> CellArray {
  let size = int.max(width * height, 0)
  fill_all_rows_gleam(array_new(size, default), 0, height, width, str, s, link)
}

fn fill_all_rows_gleam(
  arr: CellArray,
  row: Int,
  height: Int,
  width: Int,
  str: String,
  s: style.Style,
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
          s,
          link,
        )
      fill_all_rows_gleam(arr2, row + 1, height, width, str, s, link)
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
  s: style.Style,
  link: String,
) -> CellArray {
  fill_graphemes(arr, start_idx, max_idx, string.to_graphemes(str), s, link)
}

fn fill_graphemes(
  arr: CellArray,
  idx: Int,
  max_idx: Int,
  gs: List(String),
  s: style.Style,
  link: String,
) -> CellArray {
  commit(fill_draft(draft(arr), idx, max_idx, gs, s, link))
}

fn fill_draft(
  arr: Draft,
  idx: Int,
  max_idx: Int,
  gs: List(String),
  s: style.Style,
  link: String,
) -> Draft {
  case idx >= max_idx {
    True -> arr
    False ->
      case gs {
        [] -> arr
        [g, ..rest] -> {
          let w = text.grapheme_cell_width(g)
          let cell =
            Cell(content: Content(symbol: g, width: w), style: s, link: link)
          case w >= 2 {
            // A wide grapheme needs two columns. With only one left before
            // max_idx, leave the cell blank: writing the glyph anyway made it
            // overflow the clip boundary and shift everything to its right.
            True if idx + 1 >= max_idx ->
              fill_draft(arr, idx + 1, max_idx, rest, s, link)
            True ->
              fill_draft(
                draft_set(
                  idx + 1,
                  continuation_cell(s),
                  draft_set(idx, cell, arr),
                ),
                idx + 2,
                max_idx,
                rest,
                s,
                link,
              )
            False ->
              fill_draft(
                draft_set(idx, cell, arr),
                idx + 1,
                max_idx,
                rest,
                s,
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

/// One cell in the terminal grid: a grapheme + its style + optional hyperlink.
///
/// The style is resolved (see `style.resolve`): whatever it turns off has
/// already been taken off, so two cells that look the same compare equal and
/// the diff leaves them alone.
pub type Cell {
  Cell(
    content: CellContent,
    style: style.Style,
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

/// Whole style of a cell.
pub fn cell_style(cell: Cell) -> style.Style {
  cell.style
}

/// Foreground color of a cell.
pub fn cell_fg(cell: Cell) -> style.Color {
  cell.style.fg
}

/// Background color of a cell.
pub fn cell_bg(cell: Cell) -> style.Color {
  cell.style.bg
}

/// Text modifier of a cell.
pub fn cell_modifier(cell: Cell) -> style.Modifier {
  cell.style.modifier
}

/// Underline color of a cell.
pub fn cell_underline_color(cell: Cell) -> style.Color {
  cell.style.underline_color
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
    style: style.default_style(),
    link: "",
  )
}

/// Continuation cell (second column of a wide grapheme).
pub fn continuation_cell(s: style.Style) -> Cell {
  Cell(content: Continuation, style: style.resolve(s), link: "")
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
  s: style.Style,
) -> Buffer {
  let default = empty_cell()
  Buffer(
    area: area,
    cells: fill_all_rows_ffi(
      area.size.width,
      area.size.height,
      row_text,
      style.resolve(s),
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
///
/// The cell's style is resolved on the way in, like every other write path,
/// so a hand-built `Cell` cannot smuggle an unspent `sub_modifier` into the
/// grid and make an identical-looking cell compare unequal.
pub fn set_cell(buffer: Buffer, pos: geometry.Position, cell: Cell) -> Buffer {
  let cell = Cell(..cell, style: style.resolve(cell.style))
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
  s: style.Style,
) -> Buffer {
  set_string_linked(buffer, pos, str, s, "")
}

/// Set cells from a string with an OSC 8 hyperlink URI.
/// Pass `""` for no link (same as `set_string`).
pub fn set_string_linked(
  buffer: Buffer,
  pos: geometry.Position,
  str: String,
  s: style.Style,
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
          style.resolve(s),
          link,
        ),
      )
    }
  }
}

/// Clear all cells in a rect (reset to empty_cell).
/// The rect is clipped to the buffer first, so the inner loop needs no
/// per-cell bounds check and the `Buffer` record is rebuilt once, not per cell.
pub fn clear(buffer: Buffer, rect: geometry.Rect) -> Buffer {
  case geometry.intersect(buffer.area, rect) {
    Error(_) -> buffer
    Ok(r) ->
      Buffer(
        ..buffer,
        cells: commit(clear_rows(
          buffer.area,
          draft(buffer.cells),
          r,
          empty_cell(),
          r.position.y,
        )),
      )
  }
}

fn clear_rows(
  area: geometry.Rect,
  cells: Draft,
  r: geometry.Rect,
  blank: Cell,
  y: Int,
) -> Draft {
  case y >= geometry.bottom(r) {
    True -> cells
    False -> {
      let base = row_base(area, y)
      let cells2 =
        clear_row(cells, blank, base + r.position.x, base + geometry.right(r))
      clear_rows(area, cells2, r, blank, y + 1)
    }
  }
}

fn clear_row(cells: Draft, blank: Cell, idx: Int, idx_max: Int) -> Draft {
  case idx >= idx_max {
    True -> cells
    False -> clear_row(draft_set(idx, blank, cells), blank, idx + 1, idx_max)
  }
}

// Flat index of column 0 of row `y`, biased by the area origin so that
// `row_base(area, y) + x` is the index of cell (x, y).
fn row_base(area: geometry.Rect, y: Int) -> Int {
  { y - area.position.y } * area.size.width - area.position.x
}

/// Copy `src_rect` out of `src` into `dst`, placing its top-left at `dst_pos`.
/// Clipped against both buffers; anything outside either is skipped.
///
/// Use to composite an off-screen buffer (a scroll canvas, a cached panel)
/// into the frame without going cell by cell from the caller.
pub fn blit(
  dst: Buffer,
  src: Buffer,
  src_rect: geometry.Rect,
  dst_pos: geometry.Position,
) -> Buffer {
  let dx = dst_pos.x - src_rect.position.x
  let dy = dst_pos.y - src_rect.position.y
  case geometry.intersect(src.area, src_rect) {
    Error(_) -> dst
    Ok(s) -> {
      let translated =
        geometry.Rect(
          position: geometry.Position(
            x: s.position.x + dx,
            y: s.position.y + dy,
          ),
          size: s.size,
        )
      case geometry.intersect(dst.area, translated) {
        Error(_) -> dst
        Ok(d) ->
          Buffer(
            ..dst,
            cells: commit(blit_rows(
              src,
              dst.area,
              draft(dst.cells),
              d,
              dx,
              dy,
              d.position.y,
            )),
          )
      }
    }
  }
}

fn blit_rows(
  src: Buffer,
  dst_area: geometry.Rect,
  cells: Draft,
  d: geometry.Rect,
  dx: Int,
  dy: Int,
  y: Int,
) -> Draft {
  case y >= geometry.bottom(d) {
    True -> cells
    False -> {
      // Indices are expressed in destination-x, so the source base absorbs dx.
      let src_base = row_base(src.area, y - dy) - dx
      let dst_base = row_base(dst_area, y)
      let cells2 =
        blit_row(
          src.cells,
          cells,
          src_base,
          dst_base,
          d.position.x,
          d.position.x,
          geometry.right(d),
        )
      blit_rows(src, dst_area, cells2, d, dx, dy, y + 1)
    }
  }
}

fn blit_row(
  src_cells: CellArray,
  cells: Draft,
  src_base: Int,
  dst_base: Int,
  x: Int,
  x_min: Int,
  x_max: Int,
) -> Draft {
  case x >= x_max {
    True -> cells
    False -> {
      let cell = array_get(src_base + x, src_cells)
      blit_row(
        src_cells,
        draft_set(dst_base + x, clip_edge(cell, x, x_min, x_max), cells),
        src_base,
        dst_base,
        x + 1,
        x_min,
        x_max,
      )
    }
  }
}

// A window can start on the right half of a wide grapheme or end on its left
// half. Copying either half alone corrupts the row: an orphan Continuation
// renders as nothing and shifts everything after it left by a cell, while an
// orphan wide cell draws over its neighbour. Blank both.
fn clip_edge(cell: Cell, x: Int, x_min: Int, x_max: Int) -> Cell {
  case cell.content {
    Continuation if x == x_min -> empty_cell()
    Content(width: w, ..) if w >= 2 && x == x_max - 1 -> empty_cell()
    _ -> cell
  }
}

/// Restyle every cell in `rect`, keeping its content.
/// Use to tint a region (selection highlight, disabled panel) after the
/// content has been drawn.
pub fn set_style(
  buffer: Buffer,
  rect: geometry.Rect,
  s: style.Style,
) -> Buffer {
  case geometry.intersect(buffer.area, rect) {
    Error(_) -> buffer
    Ok(r) ->
      Buffer(
        ..buffer,
        cells: commit(style_rows(
          buffer.area,
          draft(buffer.cells),
          r,
          style.resolve(s),
          r.position.y,
        )),
      )
  }
}

fn style_rows(
  area: geometry.Rect,
  cells: Draft,
  r: geometry.Rect,
  s: style.Style,
  y: Int,
) -> Draft {
  case y >= geometry.bottom(r) {
    True -> cells
    False -> {
      let base = row_base(area, y)
      let cells2 =
        style_row(cells, s, base + r.position.x, base + geometry.right(r))
      style_rows(area, cells2, r, s, y + 1)
    }
  }
}

fn style_row(cells: Draft, s: style.Style, idx: Int, idx_max: Int) -> Draft {
  case idx >= idx_max {
    True -> cells
    False -> {
      let cell = draft_get(idx, cells)
      let restyled = Cell(..cell, style: s)
      style_row(draft_set(idx, restyled, cells), s, idx + 1, idx_max)
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
  // The same term cannot differ from itself. An app that keeps its last frame
  // and returns it while nothing changed pays one comparison, not a cell walk.
  // Only a hit is trusted: unequal terms may still hold equal cells, so a miss
  // takes the full path.
  case same_term(prev, next) {
    True -> []
    False -> diff_cells(prev, next)
  }
}

fn diff_cells(prev: Buffer, next: Buffer) -> List(BufferOp) {
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

// The two questions a diff asks, in the order that answers them cheapest.
//
// A steady frame compares a cell against itself far more often than against
// anything else, and identity settles that in a pointer compare. A repaint
// compares cells that differ, and there the content is what differs, so
// checking it first avoids walking the style at all. Structural equality
// alone gets one of the two cases fast and the other slow: `a == b` costs a
// full 200x50 repaint 1.7x on JavaScript, where it walks a record
// generically, and splitting it into fields costs the steady frame instead.
fn cells_equal(a: Cell, b: Cell) -> Bool {
  same_term(a, b)
  || {
    a.content == b.content && a.link == b.link && same_style(a.style, b.style)
  }
}

// Identity first, structure second. Every cell of a run written by one call
// shares a single style term, so the pointer compare settles most of them.
fn same_style(a: style.Style, b: style.Style) -> Bool {
  same_term(a, b) || a == b
}

/// True when the two are the same term, false when they merely might be
/// equal. Never the only test: a false answer means "compare properly".
@external(erlang, "etui_buffer_array_ffi", "same")
@external(javascript, "../etui_buffer_array_ffi.mjs", "same")
fn same_term(a: a, b: a) -> Bool {
  a == b
}

// ─────────────────────────────────────────────────────────────────
// ANSI rendering

// ─── Style-run tracking ──────────────────────────────────────────
// Tracks the currently applied ANSI style to avoid re-emitting unchanged
// sequences across consecutive cells. The terminal preserves style across
// cursor moves, so we can thread this state across rows and patches.

type RunStyle {
  RunStyle(style: style.Style, link: String)
}

fn blank_run_style() -> RunStyle {
  RunStyle(style: style.default_style(), link: "")
}

fn run_style_active(rs: RunStyle) -> Bool {
  style.ansi_fg(rs.style.fg) != ""
  || style.ansi_bg(rs.style.bg) != ""
  || style.ansi_modifier(rs.style.modifier) != ""
  || style.ansi_underline_color(rs.style.underline_color) != ""
  || rs.link != ""
}

// Emit a cell relative to the current RunStyle.
// When style is unchanged: emit only the text. When it changes: emit
// the minimal transition (link-close, reset, new style, link-open) then text.
fn emit_cell(rs: RunStyle, cell: Cell) -> #(String, RunStyle) {
  case is_continuation(cell) {
    True -> #("", rs)
    False -> {
      let same = cell.link == rs.link && same_style(cell.style, rs.style)
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
          let fg_seq = style.ansi_fg(cell.style.fg)
          let bg_seq = style.ansi_bg(cell.style.bg)
          let mod_seq = style.ansi_modifier(cell.style.modifier)
          let ul_seq = style.ansi_underline_color(cell.style.underline_color)
          let link_open = case cell.link {
            "" -> ""
            uri -> osc8_open(uri)
          }
          let new_rs = RunStyle(style: cell.style, link: cell.link)
          #(
            link_close
              <> reset_seq
              <> fg_seq
              <> bg_seq
              <> mod_seq
              <> ul_seq
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
