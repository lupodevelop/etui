/// File viewer + showcase of the v1.0.0 widgets.
///
/// Top half: filesystem tree (with child counts on directories) plus a
/// textarea editor for the selected file. Bottom: a showcase strip with
/// spinner, paginator, multi_select, masked input, plus a fieldset divider
/// and a short help bar.
///
/// Keys:
///   Tab            switch focus between tree and editor
///   ↑↓ / j k       navigate tree or move cursor in editor
///   Space          expand/collapse directory (tree) or toggle item (multi)
///   Enter          open file into editor (tree) or newline (editor)
///   ←→             prev/next page on the paginator
///   Backspace      delete char in editor
///   ?              toggle help short/full
///   q              quit
///
/// Run: gleam run -m etui_new_features
import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/focus
import etui/geometry.{
  type Position, type Rect, Fill, Horizontal, Length, Vertical,
}
import etui/span
import etui/style
import etui/text
import etui/widgets/block
import etui/widgets/fieldset
import etui/widgets/help
import etui/widgets/input
import etui/widgets/multi_select
import etui/widgets/paginator
import etui/widgets/scrollbar
import etui/widgets/spinner
import etui/widgets/statusbar
import etui/widgets/textarea as ta
import etui/widgets/tree
import fio
import fio/path as fio_path
import fio/types as fio_types
import gleam/int
import gleam/list
import gleam/string

// ─── Model ────────────────────────────────────────────────────────

pub type Model {
  Model(
    ring: focus.FocusRing,
    roots: List(tree.TreeNode),
    tree_state: tree.TreeState,
    editor_state: ta.TextAreaState,
    open_path: String,
    status_msg: String,
    width: Int,
    height: Int,
    quit: Bool,
    // Showcase state
    frame: Int,
    paginator: paginator.Paginator,
    multi_state: multi_select.MultiSelectState,
    password_state: input.InputState,
    help_mode: help.HelpMode,
  )
}

// ─── Filesystem helpers ───────────────────────────────────────────

fn load_tree(path: String, depth: Int) -> List(tree.TreeNode) {
  case depth <= 0 {
    True -> []
    False ->
      case fio.list(path) {
        Error(_) -> []
        Ok(names) -> {
          let sorted = list.sort(names, string.compare)
          let entries =
            list.filter_map(sorted, fn(name) {
              let full = fio_path.join(path, name)
              case fio.file_info(full) {
                Error(_) -> Error(Nil)
                Ok(info) ->
                  case fio_types.file_info_type(info) {
                    fio_types.Directory -> {
                      let children = load_tree(full, depth - 1)
                      let n =
                        tree.node(full, name <> "/", children)
                        |> tree.with_count(list.length(children))
                      Ok(n)
                    }
                    _ -> Ok(tree.leaf(full, name))
                  }
              }
            })
          let dirs =
            list.filter(entries, fn(n) {
              case n {
                tree.TreeNode(children: [_, ..], ..) -> True
                tree.TreeNode(children: [], ..) ->
                  string.ends_with(n.label, "/")
              }
            })
          let files = list.filter(entries, fn(n) { !list.contains(dirs, n) })
          list.append(dirs, files)
        }
      }
  }
}

fn open_file(path: String) -> #(ta.TextAreaState, String) {
  case fio.file_info(path) {
    Error(_) -> #(ta.state_new(), "Error: cannot stat " <> path)
    Ok(info) ->
      case info.size > 512_000 {
        True -> #(
          ta.state_from_string(
            "(file too large: " <> int.to_string(info.size) <> " bytes)",
          ),
          "Opened (truncated): " <> path,
        )
        False ->
          case fio.read(path) {
            Error(_) -> #(ta.state_new(), "Error: cannot read " <> path)
            Ok(content) -> #(ta.state_from_string(content), "Opened: " <> path)
          }
      }
  }
}

// ─── Init ─────────────────────────────────────────────────────────

fn init_model() -> Model {
  let cwd = case fio.current_directory() {
    Ok(p) -> p
    Error(_) -> "."
  }
  let roots = load_tree(cwd, 2)
  let t_widget = make_tree_widget(roots)
  // Demo paginator: 5 pages, currently on page 2.
  let p = paginator.paginator_new(5) |> paginator.go_to(1)
  // Demo multi_select: "Gleam" pre-checked.
  let ms =
    multi_select.state_new()
    |> multi_select.select_next(4)
    |> multi_select.toggle(0)
  // Demo password: prefill with a fake password.
  let pw = input.state_from_string("hunter2")
  Model(
    ring: focus.focus_new(["tree", "editor", "paginator", "multi", "password"]),
    roots: roots,
    tree_state: tree.state_from_tree(t_widget),
    editor_state: ta.state_from_string(
      "// Select a file in the tree and press Enter.\n// Tab cycles focus through every panel.",
    ),
    open_path: "",
    status_msg: "cwd: " <> cwd,
    width: 80,
    height: 24,
    quit: False,
    frame: 0,
    paginator: p,
    multi_state: ms,
    password_state: pw,
    help_mode: help.Short,
  )
}

fn make_tree_widget(roots: List(tree.TreeNode)) -> tree.TreeWidget {
  tree.tree_new(roots)
  |> tree.with_highlight_style(style.Style(
    fg: style.Indexed(15),
    bg: style.Indexed(4),
    modifier: style.bold(),
  ))
}

fn multi_items() -> List(String) {
  ["Bash", "Gleam", "Erlang", "Rust"]
}

fn help_bindings() -> List(help.Binding) {
  [
    help.binding(["tab"], "switch focus"),
    help.binding(["j", "k", "↑", "↓"], "navigate"),
    help.binding(["enter"], "open / newline"),
    help.binding([" "], "expand / toggle"),
    help.binding(["←", "→"], "prev / next page"),
    help.binding(["?"], "toggle help"),
    help.binding(["q"], "quit"),
  ]
}

fn password_widget() -> input.InputWidget {
  input.input_new("password")
  |> input.with_prompt("> ")
  |> input.with_password(True)
  |> input.with_mask("●")
}

// ─── Update ───────────────────────────────────────────────────────

fn update(event: backend.InputEvent, m: Model) -> Model {
  case event {
    backend.Tick -> Model(..m, frame: m.frame + 1)
    backend.KeyPress("q") -> Model(..m, quit: True)
    backend.KeyPress("tab") -> Model(..m, ring: focus.focus_next(m.ring))
    backend.KeyPress("?") ->
      Model(..m, help_mode: toggle_help_mode(m.help_mode))
    backend.Resize(w, h) -> Model(..m, width: w, height: h)
    backend.MouseScroll(_, _, up) ->
      case focus.focused(m.ring) {
        Ok("tree") -> scroll_tree(up, m)
        Ok("editor") -> scroll_editor(up, m)
        Ok("multi") -> scroll_multi(up, m)
        _ -> m
      }
    backend.KeyPress(k) ->
      case focus.focused(m.ring) {
        Ok("tree") -> update_tree(k, m)
        Ok("editor") -> update_editor(k, m)
        Ok("paginator") -> update_paginator(k, m)
        Ok("multi") -> update_multi(k, m)
        Ok("password") -> update_password(k, m)
        _ -> m
      }
    _ -> m
  }
}

fn toggle_help_mode(mode: help.HelpMode) -> help.HelpMode {
  case mode {
    help.Short -> help.Full
    help.Full -> help.Short
  }
}

fn scroll_tree(up: Bool, m: Model) -> Model {
  let t = make_tree_widget(m.roots)
  case up {
    True -> Model(..m, tree_state: tree.select_prev(m.tree_state, t))
    False -> Model(..m, tree_state: tree.select_next(m.tree_state, t))
  }
}

fn scroll_editor(up: Bool, m: Model) -> Model {
  let step = 3
  let s = case up {
    True ->
      list.fold(list.repeat(Nil, step), m.editor_state, fn(s, _) {
        ta.move_cursor_up(s)
      })
    False ->
      list.fold(list.repeat(Nil, step), m.editor_state, fn(s, _) {
        ta.move_cursor_down(s)
      })
  }
  Model(..m, editor_state: s)
}

fn scroll_multi(up: Bool, m: Model) -> Model {
  let count = list.length(multi_items())
  let s = case up {
    True -> multi_select.select_prev(m.multi_state)
    False -> multi_select.select_next(m.multi_state, count)
  }
  Model(..m, multi_state: s)
}

fn update_tree(k: String, m: Model) -> Model {
  let t = make_tree_widget(m.roots)
  case k {
    "up" | "k" -> Model(..m, tree_state: tree.select_prev(m.tree_state, t))
    "down" | "j" -> Model(..m, tree_state: tree.select_next(m.tree_state, t))
    " " -> Model(..m, tree_state: tree.toggle_selected(m.tree_state, t))
    "enter" ->
      case tree.selected(m.tree_state) {
        Error(_) -> m
        Ok(path) ->
          case fio.is_directory(path) {
            Ok(True) ->
              Model(..m, tree_state: tree.toggle_selected(m.tree_state, t))
            _ -> {
              let #(new_editor, msg) = open_file(path)
              Model(
                ..m,
                editor_state: new_editor,
                open_path: path,
                status_msg: msg,
                ring: focus.focus_id(m.ring, "editor"),
              )
            }
          }
      }
    _ -> m
  }
}

fn update_editor(k: String, m: Model) -> Model {
  let w = ta.textarea_new() |> ta.with_max_line_length(500)
  let s = case k {
    "enter" -> ta.newline(w, m.editor_state)
    "backspace" -> ta.backspace(m.editor_state)
    "up" -> ta.move_cursor_up(m.editor_state)
    "down" -> ta.move_cursor_down(m.editor_state)
    "left" -> ta.move_cursor_left(m.editor_state)
    "right" -> ta.move_cursor_right(m.editor_state)
    "home" -> ta.move_to_line_start(m.editor_state)
    "end" -> ta.move_to_line_end(m.editor_state)
    c -> {
      let printable = text.cell_width(c) > 0 && string.length(c) == 1
      case printable {
        True -> ta.insert_char(w, m.editor_state, c)
        False -> m.editor_state
      }
    }
  }
  Model(..m, editor_state: s)
}

fn update_paginator(k: String, m: Model) -> Model {
  case k {
    "left" | "h" -> Model(..m, paginator: paginator.prev_page(m.paginator))
    "right" | "l" -> Model(..m, paginator: paginator.next_page(m.paginator))
    _ -> m
  }
}

fn update_multi(k: String, m: Model) -> Model {
  let count = list.length(multi_items())
  let s = case k {
    "up" | "k" -> multi_select.select_prev(m.multi_state)
    "down" | "j" -> multi_select.select_next(m.multi_state, count)
    " " | "enter" -> multi_select.toggle(m.multi_state, 0)
    _ -> m.multi_state
  }
  Model(..m, multi_state: s)
}

fn update_password(k: String, m: Model) -> Model {
  let w = password_widget() |> input.with_max_length(32)
  let s = case k {
    "backspace" -> input.backspace(m.password_state)
    "left" -> input.move_cursor_left(m.password_state)
    "right" -> input.move_cursor_right(m.password_state)
    "home" -> input.move_to_start(m.password_state)
    "end" -> input.move_to_end(m.password_state)
    c -> {
      let printable = text.cell_width(c) > 0 && string.length(c) == 1
      case printable {
        True -> input.insert_char(w, m.password_state, c)
        False -> m.password_state
      }
    }
  }
  Model(..m, password_state: s)
}

// ─── Render ───────────────────────────────────────────────────────

fn render(m: Model, screen: Rect) -> #(buffer.Buffer, Result(Position, Nil)) {
  let buf = buffer.buffer_new(screen)

  // Vertical layout: content / fieldset / showcase / help / statusbar
  let help_h = case m.help_mode {
    help.Short -> 1
    help.Full -> int.min(8, list.length(help_bindings()))
  }
  let rows =
    geometry.split(Vertical, screen, [
      Fill,
      Length(1),
      Length(3),
      Length(help_h),
      Length(1),
    ])
  let #(content_area, fs_area, demo_area, help_area, status_area) = case rows {
    [c, f, d, h, s, ..] -> #(c, f, d, h, s)
    _ -> #(screen, screen, screen, screen, screen)
  }

  let tree_w = int.min(32, m.width / 3)
  let cols = geometry.split(Horizontal, content_area, [Length(tree_w), Fill])
  let #(tree_area, editor_area) = case cols {
    [t, e, ..] -> #(t, e)
    _ -> #(content_area, content_area)
  }

  // ── Tree panel (with counts) ──────────────────────────────────
  let tree_focused = focus.is_focused(m.ring, "tree")
  let tree_blk =
    block.block_new()
    |> block.with_border(block.Single)
    |> block.with_title("Files", block.Top)
    |> block.with_style(panel_border_fg(tree_focused), style.Default)
  let tree_inner = block.inner(tree_area, tree_blk)
  let buf =
    block.render(buf, tree_area, tree_blk)
    |> tree.render(tree_inner, make_tree_widget(m.roots), m.tree_state)

  // ── Editor panel ──────────────────────────────────────────────
  let editor_focused = focus.is_focused(m.ring, "editor")
  let file_name = case m.open_path {
    "" -> "Editor"
    p -> short_path(p)
  }
  let line_count = ta.line_count(m.editor_state)
  let editor_title = file_name <> "  [" <> int.to_string(line_count) <> "L]"
  let editor_blk =
    block.block_new()
    |> block.with_border(block.Single)
    |> block.with_title(editor_title, block.Top)
    |> block.with_style(panel_border_fg(editor_focused), style.Default)
  let editor_inner = block.inner(editor_area, editor_blk)
  let inner_cols = geometry.split(Horizontal, editor_inner, [Fill, Length(1)])
  let #(text_area, sb_area) = case inner_cols {
    [ta_a, sb, ..] -> #(ta_a, sb)
    _ -> #(editor_inner, editor_inner)
  }
  let e_widget =
    ta.textarea_new()
    |> ta.with_max_line_length(500)
    |> ta.with_cursor_style(style.Style(
      fg: style.Indexed(0),
      bg: style.Rgb(80, 140, 220),
      modifier: style.none(),
    ))
  let visible_h = text_area.size.height
  let scroll = ta.effective_offset(m.editor_state, visible_h)
  let sb_widget = scrollbar.scrollbar_new(line_count, visible_h, scroll)
  let buf =
    block.render(buf, editor_area, editor_blk)
    |> ta.render(text_area, e_widget, m.editor_state)
    |> scrollbar.render_vertical(sb_area, sb_widget)

  // ── Fieldset divider ──────────────────────────────────────────
  let fs =
    fieldset.fieldset_new("Showcase")
    |> fieldset.with_align(fieldset.AlignCenter)
    |> fieldset.with_line_char("─")
    |> fieldset.with_title_color(style.Rgb(120, 200, 255))
  let buf = fieldset.render(buf, fs_area, fs)

  // ── Showcase strip (4 columns: spinner / paginator / multi / password) ─
  let demo_cols =
    geometry.split(Horizontal, demo_area, [
      Length(18),
      Length(20),
      Fill,
      Length(20),
    ])
  let #(spin_area, pag_area, multi_area, pw_area) = case demo_cols {
    [a, b, c, d, ..] -> #(a, b, c, d)
    _ -> #(demo_area, demo_area, demo_area, demo_area)
  }
  let spin_w =
    spinner.spinner_new()
    |> spinner.with_style(spinner.Dots)
    |> spinner.with_label("loading")
    |> spinner.with_colors(style.Rgb(120, 200, 255), style.Default)
  let buf = spinner.render(buf, spin_area, spin_w, m.frame)

  let pag_focused = focus.is_focused(m.ring, "paginator")
  let pag = case pag_focused {
    True ->
      m.paginator
      |> paginator.with_colors(style.Rgb(255, 180, 80), style.Default)
    False -> m.paginator
  }
  let buf = paginator.render(buf, pag_area, pag)

  let multi_focused = focus.is_focused(m.ring, "multi")
  let multi_w =
    multi_select.multi_select_new(multi_items())
    |> multi_select.with_cursor_style(style.Style(
      fg: style.Indexed(0),
      bg: case multi_focused {
        True -> style.Rgb(255, 180, 80)
        False -> style.Rgb(100, 100, 100)
      },
      modifier: style.bold(),
    ))
  let buf = multi_select.render(buf, multi_area, multi_w, m.multi_state)

  let pw_focused = focus.is_focused(m.ring, "password")
  let pw_w =
    password_widget()
    |> input.with_colors(
      case pw_focused {
        True -> style.Rgb(255, 180, 80)
        False -> style.Default
      },
      style.Default,
    )
  let buf = input.render(buf, pw_area, pw_w, m.password_state)

  // ── Help bar ──────────────────────────────────────────────────
  let h =
    help.help_new(help_bindings())
    |> help.with_mode(m.help_mode)
    |> help.with_key_color(style.Rgb(255, 180, 80))
    |> help.with_description_color(style.Indexed(7))
  let buf = help.render(buf, help_area, h)

  // ── Status bar ────────────────────────────────────────────────
  let focus_label = case focus.focused(m.ring) {
    Ok(id) -> string.uppercase(id)
    _ -> ""
  }
  let bar =
    statusbar.statusbar_new()
    |> statusbar.with_left([span.line_plain(" " <> focus_label)])
    |> statusbar.with_center([span.line_plain(m.status_msg)])
    |> statusbar.with_right([span.line_plain("? help  q quit ")])
    |> statusbar.with_style(style.Indexed(15), style.Indexed(4))
  let buf = statusbar.render(buf, status_area, bar)

  // Hardware cursor: visible when editor or password focused.
  let cursor_pos = case focus.focused(m.ring) {
    Ok("editor") -> ta.cursor_screen_pos(m.editor_state, text_area)
    Ok("password") -> {
      let x = pw_area.position.x + 2 + m.password_state.cursor
      Ok(geometry.Position(x: x, y: pw_area.position.y))
    }
    _ -> Error(Nil)
  }
  #(buf, cursor_pos)
}

fn panel_border_fg(focused: Bool) -> style.Color {
  case focused {
    True -> style.Rgb(80, 160, 255)
    False -> style.Indexed(8)
  }
}

fn short_path(p: String) -> String {
  let parts = string.split(p, "/")
  case list.last(parts) {
    Ok(name) -> name
    Error(_) -> p
  }
}

// ─── Main ─────────────────────────────────────────────────────────

pub fn main() -> Nil {
  let _ =
    app.run_buffered_cursor(
      default.new_with_mouse(),
      init_model(),
      render,
      update,
      fn(m) { m.quit },
      16,
    )
  Nil
}
