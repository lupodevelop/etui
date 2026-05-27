/// Multi-line text area with wide-char-aware cursor editing.
///
/// Like `input.gleam` but supports multiple lines, cursor movement up/down,
/// and newline insertion. State is kept external.
///
/// ```gleam
/// import etui/keys
/// import etui/widgets/textarea as ta
///
/// let w = ta.textarea_new() |> ta.with_max_lines(20)
/// let state = ta.state_new()
///
/// let state = case event {
///   backend.KeyPress(k) ->
///     case keys.match(k) {
///       keys.Enter     -> ta.newline(w, state)
///       keys.Backspace -> ta.backspace(state)
///       keys.Up        -> ta.move_cursor_up(state)
///       keys.Down      -> ta.move_cursor_down(state)
///       keys.Left      -> ta.move_cursor_left(state)
///       keys.Right     -> ta.move_cursor_right(state)
///       keys.Char(c)   -> ta.insert_char(w, state, c)
///       _              -> state
///     }
///   _ -> state
/// }
///
/// let buf = ta.render(buf, area, w, state)
/// let text = ta.value(state)   // lines joined with "\n"
/// ```
import etui/buffer
import etui/geometry
import etui/style
import etui/text
import gleam/int
import gleam/list
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

/// Text area configuration.
pub type TextArea {
  TextArea(
    /// Maximum lines allowed (0 = unlimited).
    max_lines: Int,
    /// Maximum line width in cells, wide characters count as 2 (0 = unlimited).
    max_line_length: Int,
    fg: style.Color,
    bg: style.Color,
    /// Style applied to the cursor cell.
    cursor_style: style.Style,
  )
}

/// Mutable editing state.
pub type TextAreaState {
  TextAreaState(
    /// One string per line. Always at least one element.
    lines: List(String),
    /// Cursor column in cells within the current line.
    cursor_x: Int,
    /// Cursor row (0-based line index).
    cursor_y: Int,
  )
}

// ─────────────────────────────────────────────────────────────────
// Constructors

/// New textarea with default styles and no limits.
pub fn textarea_new() -> TextArea {
  TextArea(
    max_lines: 0,
    max_line_length: 0,
    fg: style.Default,
    bg: style.Default,
    cursor_style: style.Style(
      fg: style.Default,
      bg: style.Default,
      modifier: style.reverse(),
    ),
  )
}

pub fn with_max_lines(w: TextArea, n: Int) -> TextArea {
  TextArea(..w, max_lines: n)
}

pub fn with_max_line_length(w: TextArea, n: Int) -> TextArea {
  TextArea(..w, max_line_length: n)
}

pub fn with_colors(w: TextArea, fg: style.Color, bg: style.Color) -> TextArea {
  TextArea(..w, fg: fg, bg: bg)
}

pub fn with_style(w: TextArea, s: style.Style) -> TextArea {
  TextArea(..w, fg: s.fg, bg: s.bg)
}

pub fn with_cursor_style(w: TextArea, s: style.Style) -> TextArea {
  TextArea(..w, cursor_style: s)
}

// ─────────────────────────────────────────────────────────────────
// State constructors

/// Empty state: one empty line, cursor at top-left.
pub fn state_new() -> TextAreaState {
  TextAreaState(lines: [""], cursor_x: 0, cursor_y: 0)
}

/// State pre-populated from a string (splits on `\n`).
pub fn state_from_string(s: String) -> TextAreaState {
  let lines = string.split(s, "\n")
  let row = list.length(lines) - 1
  let last_line = case list.last(lines) {
    Ok(l) -> l
    Error(_) -> ""
  }
  TextAreaState(
    lines: lines,
    cursor_x: text.cell_width(last_line),
    cursor_y: int.max(0, row),
  )
}

// ─────────────────────────────────────────────────────────────────
// Value accessor

/// All lines joined with `"\n"`.
pub fn value(state: TextAreaState) -> String {
  string.join(state.lines, "\n")
}

/// Number of lines.
pub fn line_count(state: TextAreaState) -> Int {
  list.length(state.lines)
}

/// Effective scroll offset for a viewport of `visible_h` rows.
/// Returns the index of the first visible line so the cursor stays in view.
/// Pass as `offset` to `scrollbar.scrollbar_new`.
pub fn effective_offset(state: TextAreaState, visible_h: Int) -> Int {
  scroll_offset(state.cursor_y, visible_h)
}

/// Screen position of the hardware cursor within `area`.
/// Returns `Error(Nil)` when the cursor column is beyond the area width
/// (mirrors the render rule: no cursor cell is drawn off-screen).
pub fn cursor_screen_pos(
  state: TextAreaState,
  area: geometry.Rect,
) -> Result(geometry.Position, Nil) {
  case state.cursor_x >= area.size.width {
    True -> Error(Nil)
    False -> {
      let scroll = scroll_offset(state.cursor_y, area.size.height)
      Ok(geometry.Position(
        x: area.position.x + state.cursor_x,
        y: area.position.y + state.cursor_y - scroll,
      ))
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Editing operations

/// Insert a character at the current cursor position.
pub fn insert_char(
  w: TextArea,
  state: TextAreaState,
  ch: String,
) -> TextAreaState {
  let line = get_line(state.lines, state.cursor_y)
  let line_cells = text.cell_width(line)
  case w.max_line_length > 0 && line_cells >= w.max_line_length {
    True -> state
    False -> {
      let before = text.truncate(line, state.cursor_x, "")
      let after = string.drop_start(line, string.length(before))
      let new_line = before <> ch <> after
      TextAreaState(
        ..state,
        lines: set_line(state.lines, state.cursor_y, new_line),
        cursor_x: state.cursor_x + text.cell_width(ch),
      )
    }
  }
}

/// Delete the character immediately before the cursor.
/// If at column 0, merges the current line with the previous line.
pub fn backspace(state: TextAreaState) -> TextAreaState {
  case state.cursor_x > 0 {
    True -> {
      let line = get_line(state.lines, state.cursor_y)
      let before = text.truncate(line, state.cursor_x - 1, "")
      let graphemes_before =
        string.length(text.truncate(line, state.cursor_x, ""))
      let after = string.drop_start(line, graphemes_before)
      TextAreaState(
        ..state,
        lines: set_line(state.lines, state.cursor_y, before <> after),
        cursor_x: text.cell_width(before),
      )
    }
    False ->
      case state.cursor_y > 0 {
        False -> state
        True -> {
          let prev = get_line(state.lines, state.cursor_y - 1)
          let curr = get_line(state.lines, state.cursor_y)
          let merged = prev <> curr
          let new_x = text.cell_width(prev)
          let new_lines =
            delete_line(state.lines, state.cursor_y)
            |> set_line(state.cursor_y - 1, merged)
          TextAreaState(
            lines: new_lines,
            cursor_x: new_x,
            cursor_y: state.cursor_y - 1,
          )
        }
      }
  }
}

/// Insert a newline at the cursor. Splits the current line.
pub fn newline(w: TextArea, state: TextAreaState) -> TextAreaState {
  let n_lines = list.length(state.lines)
  case w.max_lines > 0 && n_lines >= w.max_lines {
    True -> state
    False -> {
      let line = get_line(state.lines, state.cursor_y)
      let before = text.truncate(line, state.cursor_x, "")
      let after = string.drop_start(line, string.length(before))
      let new_lines =
        set_line(state.lines, state.cursor_y, before)
        |> insert_line_after(state.cursor_y, after)
      TextAreaState(lines: new_lines, cursor_x: 0, cursor_y: state.cursor_y + 1)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Cursor movement

/// Move cursor one cell left. Wraps to end of previous line.
pub fn move_cursor_left(state: TextAreaState) -> TextAreaState {
  case state.cursor_x > 0 {
    True -> {
      let line = get_line(state.lines, state.cursor_y)
      let new_x = text.cell_width(text.truncate(line, state.cursor_x - 1, ""))
      TextAreaState(..state, cursor_x: new_x)
    }
    False ->
      case state.cursor_y > 0 {
        False -> state
        True -> {
          let prev = get_line(state.lines, state.cursor_y - 1)
          TextAreaState(
            ..state,
            cursor_x: text.cell_width(prev),
            cursor_y: state.cursor_y - 1,
          )
        }
      }
  }
}

/// Move cursor one cell right. Wraps to start of next line.
pub fn move_cursor_right(state: TextAreaState) -> TextAreaState {
  let line = get_line(state.lines, state.cursor_y)
  case state.cursor_x < text.cell_width(line) {
    True -> {
      let step = grapheme_width_at(line, state.cursor_x)
      TextAreaState(..state, cursor_x: state.cursor_x + step)
    }
    False -> {
      let n_lines = list.length(state.lines)
      case state.cursor_y < n_lines - 1 {
        False -> state
        True ->
          TextAreaState(..state, cursor_x: 0, cursor_y: state.cursor_y + 1)
      }
    }
  }
}

/// Move cursor up one line, clamping x to the new line's width.
pub fn move_cursor_up(state: TextAreaState) -> TextAreaState {
  case state.cursor_y > 0 {
    False -> state
    True -> {
      let new_y = state.cursor_y - 1
      let prev = get_line(state.lines, new_y)
      TextAreaState(
        ..state,
        cursor_x: snap_to_boundary(prev, state.cursor_x),
        cursor_y: new_y,
      )
    }
  }
}

/// Move cursor down one line, clamping x to the new line's width.
pub fn move_cursor_down(state: TextAreaState) -> TextAreaState {
  let n_lines = list.length(state.lines)
  case state.cursor_y < n_lines - 1 {
    False -> state
    True -> {
      let new_y = state.cursor_y + 1
      let next = get_line(state.lines, new_y)
      TextAreaState(
        ..state,
        cursor_x: snap_to_boundary(next, state.cursor_x),
        cursor_y: new_y,
      )
    }
  }
}

/// Move cursor to beginning of current line.
pub fn move_to_line_start(state: TextAreaState) -> TextAreaState {
  TextAreaState(..state, cursor_x: 0)
}

/// Move cursor to end of current line.
pub fn move_to_line_end(state: TextAreaState) -> TextAreaState {
  let line = get_line(state.lines, state.cursor_y)
  TextAreaState(..state, cursor_x: text.cell_width(line))
}

/// Delete from cursor to end of current line.
pub fn delete_to_line_end(state: TextAreaState) -> TextAreaState {
  let line = get_line(state.lines, state.cursor_y)
  let before = text.truncate(line, state.cursor_x, "")
  TextAreaState(..state, lines: set_line(state.lines, state.cursor_y, before))
}

// ─────────────────────────────────────────────────────────────────
// Rendering

/// Render the textarea. Scrolls vertically so the cursor line is visible.
/// Highlights the cursor cell with `cursor_style`.
pub fn render(
  buf: buffer.Buffer,
  area: geometry.Rect,
  w: TextArea,
  state: TextAreaState,
) -> buffer.Buffer {
  case area.size.height <= 0 || area.size.width <= 0 {
    True -> buf
    False -> {
      let visible_h = area.size.height
      let scroll = scroll_offset(state.cursor_y, visible_h)
      render_lines(buf, area, w, state, scroll, 0)
    }
  }
}

fn render_lines(
  buf: buffer.Buffer,
  area: geometry.Rect,
  w: TextArea,
  state: TextAreaState,
  scroll: Int,
  row_offset: Int,
) -> buffer.Buffer {
  case row_offset >= area.size.height {
    True -> buf
    False -> {
      let line_idx = scroll + row_offset
      let line = get_line(state.lines, line_idx)
      let y = area.position.y + row_offset
      let is_cursor_row = line_idx == state.cursor_y
      let buf2 = render_line(buf, area, w, state, line, y, is_cursor_row)
      render_lines(buf2, area, w, state, scroll, row_offset + 1)
    }
  }
}

fn render_line(
  buf: buffer.Buffer,
  area: geometry.Rect,
  w: TextArea,
  state: TextAreaState,
  line: String,
  y: Int,
  is_cursor_row: Bool,
) -> buffer.Buffer {
  let width = area.size.width
  let truncated = text.truncate(line, width, "")
  let padded = text.pad_right(truncated, width)
  let buf2 =
    buffer.set_string(
      buf,
      geometry.Position(x: area.position.x, y: y),
      padded,
      w.fg,
      w.bg,
      style.none(),
    )
  case is_cursor_row && state.cursor_x < width {
    False -> buf2
    True -> {
      let cursor_ch = grapheme_at_cell(line, state.cursor_x)
      buffer.set_string(
        buf2,
        geometry.Position(x: area.position.x + state.cursor_x, y: y),
        cursor_ch,
        w.cursor_style.fg,
        w.cursor_style.bg,
        w.cursor_style.modifier,
      )
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Internal helpers

fn get_line(lines: List(String), idx: Int) -> String {
  case idx < 0 {
    True -> ""
    False ->
      case list.drop(lines, idx) {
        [h, ..] -> h
        [] -> ""
      }
  }
}

fn set_line(lines: List(String), idx: Int, new_val: String) -> List(String) {
  list.index_map(lines, fn(line, i) {
    case i == idx {
      True -> new_val
      False -> line
    }
  })
}

fn delete_line(lines: List(String), idx: Int) -> List(String) {
  list.index_fold(lines, [], fn(acc, line, i) {
    case i == idx {
      True -> acc
      False -> list.append(acc, [line])
    }
  })
}

fn insert_line_after(
  lines: List(String),
  idx: Int,
  new_line: String,
) -> List(String) {
  insert_line_after_loop(lines, idx, new_line, 0, [])
}

fn insert_line_after_loop(
  lines: List(String),
  idx: Int,
  new_line: String,
  i: Int,
  acc: List(String),
) -> List(String) {
  case lines {
    [] -> list.reverse(acc)
    [h, ..rest] -> {
      let acc2 = case i == idx {
        True -> [new_line, h, ..acc]
        False -> [h, ..acc]
      }
      insert_line_after_loop(rest, idx, new_line, i + 1, acc2)
    }
  }
}

fn scroll_offset(cursor_y: Int, visible_h: Int) -> Int {
  case visible_h <= 0 {
    True -> 0
    False ->
      case cursor_y < visible_h {
        True -> 0
        False -> cursor_y - visible_h + 1
      }
  }
}

// Clamp cell_pos to the nearest grapheme boundary ≤ cell_pos in s.
// Prevents cursor landing mid-wide-char (e.g. inside a 2-cell emoji).
fn snap_to_boundary(s: String, cell_pos: Int) -> Int {
  let clamped = int.min(cell_pos, text.cell_width(s))
  text.cell_width(text.truncate(s, clamped, ""))
}

fn grapheme_width_at(s: String, cell_pos: Int) -> Int {
  let prefix = text.truncate(s, cell_pos, "")
  let rest = string.drop_start(s, string.length(prefix))
  case string.to_graphemes(rest) {
    [g, ..] -> text.cell_width(g)
    [] -> 1
  }
}

fn grapheme_at_cell(s: String, cell_pos: Int) -> String {
  let prefix = text.truncate(s, cell_pos, "")
  let rest = string.drop_start(s, string.length(prefix))
  case string.to_graphemes(rest) {
    [g, ..] -> g
    [] -> " "
  }
}
