/// File browser TUI, M7 exit criterion.
///
/// Demonstrates: geometry.split, block, paragraph, list, scrollbar,
/// span/Line for colored details, mouse support (click + scroll),
/// app.run event loop, and fio for real filesystem access.
///
/// Run: gleam run -m etui_filebrowser
/// Keys: j/↓ down, k/↑ up, Enter cd into dir, u/h go up, q quit.
/// Mouse: scroll wheel to navigate, left-click to select, double-click Enter to cd.
import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/geometry.{rect_new}
import etui/keys
import etui/span
import etui/style
import etui/widgets/block
import etui/widgets/list as list_widget
import etui/widgets/paragraph
import etui/widgets/scrollbar
import fio
import fio/path as fio_path
import fio/types as fio_types
import gleam/int
import gleam/list
import gleam/string

// ─── Model ────────────────────────────────────────────────────────

pub type Entry {
  Entry(name: String, is_dir: Bool, size: Int)
}

pub type Model {
  Model(
    path: String,
    entries: List(Entry),
    list_state: list_widget.ListState,
    width: Int,
    height: Int,
    quit: Bool,
  )
}

// ─── Filesystem helpers ───────────────────────────────────────────

fn load_dir(path: String) -> Result(List(Entry), Nil) {
  case fio.list(path) {
    Error(_) -> Error(Nil)
    Ok(names) -> {
      let sorted_names = list.sort(names, string.compare)
      let entries =
        list.filter_map(sorted_names, fn(name) {
          let full_path = fio_path.join(path, name)
          case fio.file_info(full_path) {
            Error(_) -> Error(Nil)
            Ok(info) -> {
              let is_dir = case fio_types.file_info_type(info) {
                fio_types.Directory -> True
                _ -> False
              }
              Ok(Entry(name: name, is_dir: is_dir, size: info.size))
            }
          }
        })
      let dirs = list.filter(entries, fn(e) { e.is_dir })
      let files = list.filter(entries, fn(e) { !e.is_dir })
      Ok(list.append(dirs, files))
    }
  }
}

fn initial_model() -> Model {
  let path = case fio.current_directory() {
    Ok(p) -> p
    Error(_) -> "."
  }
  let entries = case load_dir(path) {
    Ok(es) -> es
    Error(_) -> []
  }
  Model(
    path: path,
    entries: entries,
    list_state: list_widget.state_new(),
    width: 80,
    height: 24,
    quit: False,
  )
}

fn get_selected_entry(model: Model) -> Result(Entry, Nil) {
  list_at(model.entries, model.list_state.selected)
}

fn list_at(items: List(a), idx: Int) -> Result(a, Nil) {
  case idx < 0 {
    True -> Error(Nil)
    False ->
      case items {
        [] -> Error(Nil)
        [h, ..] if idx == 0 -> Ok(h)
        [_, ..rest] -> list_at(rest, idx - 1)
      }
  }
}

fn go_up(model: Model) -> Model {
  let parent = fio_path.directory_name(model.path)
  case parent == model.path {
    True -> model
    False ->
      case load_dir(parent) {
        Ok(entries) ->
          Model(
            ..model,
            path: parent,
            entries: entries,
            list_state: list_widget.state_new(),
          )
        Error(_) -> model
      }
  }
}

fn enter_selected(model: Model) -> Model {
  case get_selected_entry(model) {
    Ok(entry) if entry.is_dir -> {
      let new_path = fio_path.join(model.path, entry.name)
      case load_dir(new_path) {
        Ok(entries) ->
          Model(
            ..model,
            path: new_path,
            entries: entries,
            list_state: list_widget.state_new(),
          )
        Error(_) -> model
      }
    }
    _ -> model
  }
}

// ─── Layout helpers (shared between render and update) ────────────

fn layout(
  model: Model,
) -> #(
  geometry.Rect,
  geometry.Rect,
  geometry.Rect,
  geometry.Rect,
  geometry.Rect,
) {
  let screen = rect_new(0, 0, model.width, model.height)
  let sections =
    geometry.split(geometry.Vertical, screen, [
      geometry.Fill,
      geometry.Length(1),
    ])
  let #(main_area, status_area) = case sections {
    [m, s, ..] -> #(m, s)
    [m] -> #(m, rect_new(0, model.height - 1, model.width, 1))
    [] -> #(screen, rect_new(0, 0, 0, 0))
  }
  let panels =
    geometry.split(geometry.Horizontal, main_area, [
      geometry.Percentage(40),
      geometry.Fill,
    ])
  let #(left_area, right_area) = case panels {
    [l, r, ..] -> #(l, r)
    [l] -> #(l, rect_new(l.size.width, 0, 0, main_area.size.height))
    [] -> #(main_area, rect_new(0, 0, 0, 0))
  }

  let files_block =
    block.block_new()
    |> block.with_border(block.Single)

  let list_inner = block.inner(left_area, files_block)
  // Split list inner: [Fill, Length(1)] → list column + scrollbar column
  let inner_cols =
    geometry.split(geometry.Horizontal, list_inner, [
      geometry.Fill,
      geometry.Length(1),
    ])
  let #(list_col, scroll_col) = case inner_cols {
    [lc, sc, ..] -> #(lc, sc)
    [lc] -> #(lc, rect_new(lc.size.width, lc.position.y, 0, lc.size.height))
    [] -> #(list_inner, rect_new(0, 0, 0, 0))
  }
  #(left_area, right_area, status_area, list_col, scroll_col)
}

// ─── Rendering ────────────────────────────────────────────────────

fn format_size(bytes: Int) -> String {
  case bytes {
    n if n >= 1_073_741_824 -> int.to_string(n / 1_073_741_824) <> " GB"
    n if n >= 1_048_576 -> int.to_string(n / 1_048_576) <> " MB"
    n if n >= 1024 -> int.to_string(n / 1024) <> " KB"
    n -> int.to_string(n) <> " B"
  }
}

fn entry_display_name(e: Entry) -> String {
  case e.is_dir {
    True -> e.name <> "/"
    False -> e.name
  }
}

// Returns detail lines as span.Line for colored display.
fn detail_span_lines(entry: Result(Entry, Nil)) -> List(span.Line) {
  let label_style =
    style.Style(fg: style.Default, bg: style.Default, modifier: style.bold())
  case entry {
    Error(_) -> [span.line_plain("(nothing selected)")]
    Ok(e) -> {
      let type_color = case e.is_dir {
        True -> style.Indexed(12)
        False -> style.Default
      }
      let size_color = style.Indexed(11)
      [
        span.line_new([
          span.span_styled("Name: ", label_style),
          span.span_plain(e.name),
        ]),
        span.line_new([
          span.span_styled("Type: ", label_style),
          span.span_plain(case e.is_dir {
            True -> "Directory"
            False -> "File"
          })
            |> span.span_fg(type_color),
        ]),
        span.line_new([
          span.span_styled("Size: ", label_style),
          span.span_plain(format_size(e.size))
            |> span.span_fg(size_color),
        ]),
      ]
    }
  }
}

fn render(model: Model) -> List(backend.RenderOp) {
  let screen = rect_new(0, 0, model.width, model.height)
  let #(left_area, right_area, status_area, list_col, scroll_col) =
    layout(model)

  let files_block =
    block.block_new()
    |> block.with_border(block.Single)
    |> block.with_title("Files  (↑↓/jk  →/Enter  ←/u  q)", block.Top)

  let details_block =
    block.block_new()
    |> block.with_border(block.Rounded)
    |> block.with_title("Details", block.Top)

  let item_names = list.map(model.entries, entry_display_name)
  let file_list = list_widget.list_new(item_names)

  let detail_inner = block.inner(right_area, details_block)
  let detail_lines = detail_span_lines(get_selected_entry(model))

  let status_text =
    " "
    <> model.path
    <> "  ("
    <> int.to_string(list.length(model.entries))
    <> " items)"
  let status_para = paragraph.paragraph_new(status_text)

  let sb =
    scrollbar.scrollbar_new(
      list.length(model.entries),
      list_col.size.height,
      list_widget.effective_offset(model.list_state, list_col.size.height),
    )
    |> scrollbar.with_arrows("", "")

  let buf =
    buffer.buffer_new(screen)
    |> block.render(left_area, files_block)
    |> list_widget.render_stateful(list_col, file_list, model.list_state)
    |> scrollbar.render_vertical(scroll_col, sb)
    |> block.render(right_area, details_block)
    |> paragraph.render_styled(detail_inner, detail_lines)
    |> paragraph.render(status_area, status_para)

  [
    backend.ClearScreen,
    backend.MoveCursor(0, 0),
    backend.Write(buf_to_ansi(buf)),
  ]
}

// ─── Buffer → ANSI string ─────────────────────────────────────────

fn move_cursor_seq(x: Int, y: Int) -> String {
  "\u{001B}[" <> int.to_string(y + 1) <> ";" <> int.to_string(x + 1) <> "H"
}

fn buf_to_ansi(buf: buffer.Buffer) -> String {
  let area = buffer.area(buf)
  let x0 = area.position.x
  let y0 = area.position.y
  let w = area.size.width
  let h = area.size.height
  rows_to_ansi(buf, x0, y0, w, h, 0, "")
}

fn rows_to_ansi(
  buf: buffer.Buffer,
  x0: Int,
  y0: Int,
  w: Int,
  h: Int,
  row: Int,
  acc: String,
) -> String {
  case row >= h {
    True -> acc <> style.ansi_reset()
    False -> {
      let row_str =
        move_cursor_seq(x0, y0 + row)
        <> row_to_ansi(buf, x0, y0 + row, w, 0, "")
      rows_to_ansi(buf, x0, y0, w, h, row + 1, acc <> row_str)
    }
  }
}

fn row_to_ansi(
  buf: buffer.Buffer,
  x0: Int,
  y: Int,
  w: Int,
  col: Int,
  acc: String,
) -> String {
  case col >= w {
    True -> acc
    False -> {
      let pos = geometry.Position(x: x0 + col, y: y)
      let cell = buffer.get_cell(buf, pos)
      let s = case buffer.is_continuation(cell) {
        True -> ""
        False -> {
          let fg_seq = style.ansi_fg(buffer.cell_fg(cell))
          let bg_seq = style.ansi_bg(buffer.cell_bg(cell))
          let mod_seq = style.ansi_modifier(buffer.cell_modifier(cell))
          let needs_reset = fg_seq != "" || bg_seq != "" || mod_seq != ""
          let reset = case needs_reset {
            True -> style.ansi_reset()
            False -> ""
          }
          fg_seq <> bg_seq <> mod_seq <> buffer.cell_symbol(cell) <> reset
        }
      }
      row_to_ansi(buf, x0, y, w, col + 1, acc <> s)
    }
  }
}

// ─── Event handler ────────────────────────────────────────────────

fn update(event: backend.InputEvent, model: Model) -> Model {
  case event {
    backend.KeyPress(k) ->
      case keys.match(k) {
        keys.Char("q") | keys.Char("Q") -> Model(..model, quit: True)
        keys.Down | keys.Char("j") ->
          Model(
            ..model,
            list_state: list_widget.select_next(
              model.list_state,
              list.length(model.entries),
            ),
          )
        keys.Up | keys.Char("k") ->
          Model(..model, list_state: list_widget.select_prev(model.list_state))
        keys.Enter | keys.Right -> enter_selected(model)
        keys.Left | keys.Char("u") | keys.Char("h") -> go_up(model)
        _ -> model
      }
    backend.Resize(w, h) -> Model(..model, width: w, height: h)
    backend.MouseScroll(_, _, True) ->
      Model(..model, list_state: list_widget.select_prev(model.list_state))
    backend.MouseScroll(_, _, False) ->
      Model(
        ..model,
        list_state: list_widget.select_next(
          model.list_state,
          list.length(model.entries),
        ),
      )
    backend.MousePress(x, y, backend.MouseLeft) -> {
      let #(_left, _right, _status, list_col, _scroll) = layout(model)
      let in_col =
        x >= list_col.position.x
        && x < list_col.position.x + list_col.size.width
        && y >= list_col.position.y
        && y < list_col.position.y + list_col.size.height
      case in_col {
        False -> model
        True -> {
          let effective =
            list_widget.effective_offset(model.list_state, list_col.size.height)
          let clicked = y - list_col.position.y + effective
          let clamped = int.clamp(clicked, 0, list.length(model.entries) - 1)
          Model(
            ..model,
            list_state: list_widget.select(model.list_state, clamped),
          )
        }
      }
    }
    _ -> model
  }
}

// ─── Entry point ──────────────────────────────────────────────────

pub fn main() -> Nil {
  let model = initial_model()
  let b = default.new()
  let _ = app.run(b, model, render, update, fn(m) { m.quit }, 16)
  Nil
}
