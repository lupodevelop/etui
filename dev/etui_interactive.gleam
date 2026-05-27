/// Interactive Etui demo, full feature showcase.
/// TAB/←→=pagina  ↑↓=nav  b=blink  q=quit
import etui/anim
import etui/app
import etui/backend
import etui/backend/default
import etui/buffer
import etui/geometry.{type Rect, Position, Rect, Size}
import etui/style
import etui/text
import etui/widgets/block as gblock_widget
import etui/widgets/canvas as gcanvas_widget
import etui/widgets/chart as gchart_widget
import etui/widgets/gauge as ggauge_widget
import etui/widgets/gradient_bar as ggradient_widget
import etui/widgets/hbar as ghbar_widget
import etui/widgets/input as ginput_widget
import etui/widgets/list as glist_widget
import etui/widgets/marquee as gmarquee_widget
import etui/widgets/progress as gprogress_widget
import etui/widgets/scene as gscene_widget
import etui/widgets/sparkline as gspark_widget
import etui/widgets/spinner as gspinner_widget
import etui/widgets/table as gtable_widget
import etui/widgets/tabs as gtabs_widget
import gleam/int
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

type Focus {
  FocusList
  FocusTable
  FocusSearch
  FocusCursor
  FocusProgress
  FocusGauge
  FocusChart
  FocusAnimations
  FocusHBar
  FocusCanvas
  FocusScene
}

type AppState {
  AppState(
    focus: Focus,
    list_state: glist_widget.ListState,
    table_state: gtable_widget.TableState,
    input_state: ginput_widget.InputState,
    cursor_idx: Int,
    progress_pct: Int,
    gauge_pct: Int,
    chart_fill_idx: Int,
    blink_list: Bool,
    blink_table: Bool,
    anim: anim.AnimState,
    quit: Bool,
  )
}

// ─────────────────────────────────────────────────────────────────
// Main

pub fn main() -> Nil {
  let state =
    AppState(
      focus: FocusList,
      list_state: glist_widget.state_new(),
      table_state: gtable_widget.state_new(),
      input_state: ginput_widget.state_new(),
      cursor_idx: 0,
      progress_pct: 50,
      gauge_pct: 65,
      chart_fill_idx: 0,
      blink_list: False,
      blink_table: False,
      anim: anim.anim_new(),
      quit: False,
    )
  let _ =
    app.run_buffered_cursor(
      default.new(),
      state,
      fn(s, screen) { #(render(s, screen), Error(Nil)) },
      on_event,
      fn(s) { s.quit },
      100,
    )
  Nil
}

// ─────────────────────────────────────────────────────────────────
// Event handler

fn on_event(event: backend.InputEvent, state: AppState) -> AppState {
  case event {
    backend.KeyPress("q") -> AppState(..state, quit: True)
    backend.KeyPress("tab") -> AppState(..state, focus: next_focus(state.focus))
    backend.KeyPress("up") -> handle_up(state)
    backend.KeyPress("down") -> handle_down(state)
    backend.KeyPress("right") -> handle_right(state)
    backend.KeyPress("left") -> handle_left(state)
    backend.KeyPress("backspace") -> handle_backspace(state)
    backend.KeyPress(c) -> handle_char(state, c)
    backend.Tick -> AppState(..state, anim: anim.tick(state.anim))
    _ -> state
  }
}

fn handle_up(state: AppState) -> AppState {
  case state.focus {
    FocusList ->
      AppState(..state, list_state: glist_widget.select_prev(state.list_state))
    FocusTable ->
      AppState(
        ..state,
        table_state: gtable_widget.select_prev_row(state.table_state),
      )
    FocusCursor ->
      AppState(..state, cursor_idx: int.max(0, state.cursor_idx - 1))
    FocusProgress ->
      AppState(
        ..state,
        progress_pct: int.clamp(state.progress_pct + 10, 0, 100),
      )
    FocusGauge ->
      AppState(..state, gauge_pct: int.clamp(state.gauge_pct + 10, 0, 100))
    FocusChart ->
      AppState(..state, chart_fill_idx: { state.chart_fill_idx + 4 } % 5)
    FocusSearch | FocusAnimations | FocusHBar | FocusCanvas | FocusScene ->
      state
  }
}

fn handle_down(state: AppState) -> AppState {
  case state.focus {
    FocusList ->
      AppState(
        ..state,
        list_state: glist_widget.select_next(state.list_state, 10),
      )
    FocusTable ->
      AppState(
        ..state,
        table_state: gtable_widget.select_next_row(state.table_state, 15),
      )
    FocusCursor ->
      AppState(..state, cursor_idx: int.min(5, state.cursor_idx + 1))
    FocusProgress ->
      AppState(
        ..state,
        progress_pct: int.clamp(state.progress_pct - 10, 0, 100),
      )
    FocusGauge ->
      AppState(..state, gauge_pct: int.clamp(state.gauge_pct - 10, 0, 100))
    FocusChart ->
      AppState(..state, chart_fill_idx: { state.chart_fill_idx + 1 } % 5)
    FocusSearch | FocusAnimations | FocusHBar | FocusCanvas | FocusScene ->
      state
  }
}

fn handle_right(state: AppState) -> AppState {
  case state.focus {
    FocusProgress ->
      AppState(..state, progress_pct: int.min(100, state.progress_pct + 1))
    FocusGauge ->
      AppState(..state, gauge_pct: int.min(100, state.gauge_pct + 1))
    _ -> AppState(..state, focus: next_focus(state.focus))
  }
}

fn handle_left(state: AppState) -> AppState {
  case state.focus {
    FocusProgress ->
      AppState(..state, progress_pct: int.max(0, state.progress_pct - 1))
    FocusGauge -> AppState(..state, gauge_pct: int.max(0, state.gauge_pct - 1))
    _ -> AppState(..state, focus: prev_focus(state.focus))
  }
}

fn handle_char(state: AppState, c: String) -> AppState {
  case state.focus {
    FocusSearch -> {
      let widget =
        ginput_widget.input_new("Ricerca...")
        |> ginput_widget.with_max_length(50)
      AppState(
        ..state,
        input_state: ginput_widget.insert_char(widget, state.input_state, c),
      )
    }
    _ ->
      case c {
        "b" ->
          AppState(
            ..state,
            blink_list: !state.blink_list,
            blink_table: !state.blink_table,
          )
        _ -> state
      }
  }
}

fn handle_backspace(state: AppState) -> AppState {
  case state.focus {
    FocusSearch ->
      AppState(..state, input_state: ginput_widget.backspace(state.input_state))
    _ -> state
  }
}

fn next_focus(f: Focus) -> Focus {
  case f {
    FocusList -> FocusTable
    FocusTable -> FocusSearch
    FocusSearch -> FocusCursor
    FocusCursor -> FocusProgress
    FocusProgress -> FocusGauge
    FocusGauge -> FocusChart
    FocusChart -> FocusAnimations
    FocusAnimations -> FocusHBar
    FocusHBar -> FocusCanvas
    FocusCanvas -> FocusScene
    FocusScene -> FocusList
  }
}

fn prev_focus(f: Focus) -> Focus {
  case f {
    FocusList -> FocusScene
    FocusTable -> FocusList
    FocusSearch -> FocusTable
    FocusCursor -> FocusSearch
    FocusProgress -> FocusCursor
    FocusGauge -> FocusProgress
    FocusChart -> FocusGauge
    FocusAnimations -> FocusChart
    FocusHBar -> FocusAnimations
    FocusCanvas -> FocusHBar
    FocusScene -> FocusCanvas
  }
}

// ─────────────────────────────────────────────────────────────────
// Cursor shape helpers

fn cursor_shape_name(idx: Int) -> String {
  case idx {
    0 -> "Bar blink"
    1 -> "Bar steady"
    2 -> "Block blink"
    3 -> "Block steady"
    4 -> "Underline blink"
    _ -> "Underline steady"
  }
}

fn cursor_shape_code(idx: Int) -> String {
  case idx {
    0 -> "\\e[5 q"
    1 -> "\\e[6 q"
    2 -> "\\e[1 q"
    3 -> "\\e[2 q"
    4 -> "\\e[3 q"
    _ -> "\\e[4 q"
  }
}

fn cursor_shape_preview(idx: Int) -> String {
  case idx {
    0 | 1 -> "▎"
    2 | 3 -> "█"
    _ -> "▁"
  }
}

// ─────────────────────────────────────────────────────────────────
// Layout helper: inner area of a bordered block (1px border)

fn inner(area: Rect) -> Rect {
  Rect(
    Position(area.position.x + 1, area.position.y + 1),
    Size(int.max(0, area.size.width - 2), int.max(0, area.size.height - 2)),
  )
}

// ─────────────────────────────────────────────────────────────────
// Rendering

fn render(state: AppState, screen: Rect) -> buffer.Buffer {
  let w = screen.size.width
  let h = screen.size.height
  let buf = buffer.buffer_new(screen)
  let content = Rect(Position(0, 1), Size(w, h - 2))

  // Tab bar (row 0)
  let active_tab = case state.focus {
    FocusList -> 0
    FocusTable -> 1
    FocusSearch -> 2
    FocusCursor -> 3
    FocusProgress -> 4
    FocusGauge -> 5
    FocusChart -> 6
    FocusAnimations -> 7
    FocusHBar -> 8
    FocusCanvas -> 9
    FocusScene -> 10
  }
  let buf =
    gtabs_widget.render(
      buf,
      Rect(Position(0, 0), Size(w, 1)),
      gtabs_widget.tabs_new([
        "LISTA", "TABELLA", "RICERCA", "CURSORI", "PROG", "GAUGE", "CHART",
        "ANIM", "HBAR", "CANVAS", "SCENA",
      ])
        |> gtabs_widget.with_active(active_tab)
        |> gtabs_widget.with_divider("│")
        |> gtabs_widget.with_padding(1),
    )

  // Page content
  let buf = case state.focus {
    FocusList -> page_lista(buf, content, state)
    FocusTable -> page_tabella(buf, content, state)
    FocusSearch -> page_ricerca(buf, content, state)
    FocusCursor -> page_cursori(buf, content, state)
    FocusProgress -> page_progress(buf, content, state)
    FocusGauge -> page_gauge(buf, content, state)
    FocusChart -> page_chart(buf, content, state)
    FocusAnimations -> page_animazioni(buf, content, state)
    FocusHBar -> page_hbar(buf, content, state)
    FocusCanvas -> page_canvas(buf, content, state)
    FocusScene -> page_scene(buf, content, state)
  }

  // Status bar (row h-1)
  buffer.set_string(
    buf,
    Position(0, h - 1),
    make_status(state, w),
    style.Default,
    style.Default,
    style.reverse(),
  )
}

fn make_status(state: AppState, w: Int) -> String {
  let s = case state.focus {
    FocusList -> "[LISTA]  TAB/←→=pagina  ↑↓=nav  b=blink  q=quit"
    FocusTable -> "[TABELLA]  TAB/←→=pagina  ↑↓=nav  b=blink  q=quit"
    FocusSearch -> "[RICERCA]  TAB/←→=pagina  digita=input  ⌫=del  q=quit"
    FocusCursor -> "[CURSORI]  TAB/←→=pagina  ↑↓=seleziona forma  q=quit"
    FocusProgress -> "[PROG]  TAB/←→=pagina  ↑↓=±10  ←→=±1  q=quit"
    FocusGauge -> "[GAUGE]  TAB/←→=pagina  ↑↓=±10  ←→=±1  q=quit"
    FocusChart -> "[CHART]  TAB/←→=pagina  ↑↓=cambia fill  q=quit"
    FocusAnimations -> "[ANIM]  TAB/←→=pagina  q=quit"
    FocusHBar -> "[HBAR]  TAB/←→=pagina  q=quit"
    FocusCanvas -> "[CANVAS]  TAB/←→=pagina  q=quit"
    FocusScene -> "[SCENA]  TAB/←→=pagina  q=quit"
  }
  text.pad_right(s, w)
}

// ─────────────────────────────────────────────────────────────────
// PAGE: LISTA, lista widget + sparklines + spinners

fn page_lista(
  buf: buffer.Buffer,
  area: Rect,
  state: AppState,
) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height
  let lw = int.min(32, w / 3)
  let rw = int.max(1, w - lw - 1)
  let rx = area.position.x + lw + 1

  // Left: bordered lista
  let left = Rect(Position(area.position.x, area.position.y), Size(lw, ch))
  let buf =
    gblock_widget.render(
      buf,
      left,
      gblock_widget.block_new()
        |> gblock_widget.with_border(gblock_widget.Rounded)
        |> gblock_widget.with_title("LISTA  ↑↓=nav", gblock_widget.Top),
    )
  let list_items = [
    "Home", "Widgets", "Sparkline", "Chart", "Gauge", "Cursori", "Progress",
    "Animazioni", "Ricerca", "Impostazioni",
  ]
  let blink_p = case state.blink_list {
    True -> 6
    False -> 0
  }
  let buf =
    glist_widget.render_animated(
      buf,
      inner(left),
      glist_widget.list_new(list_items) |> glist_widget.with_blink(blink_p),
      state.list_state,
      state.anim.frame,
    )

  // Right: sparklines
  let buf =
    buffer.set_string(
      buf,
      Position(rx, area.position.y),
      text.pad_right("SPARKLINE WIDGET  (5 varianti fill)", rw),
      style.Default,
      style.Default,
      style.bold(),
    )
  let wave = fn(phase) {
    range(0, rw)
    |> list.map(fn(x) {
      anim.oscillate(0, 100, state.anim.frame + x * 3 + phase, 50)
    })
  }
  let fills = [
    #(gspark_widget.SparkAnimatedRainbow, "SparkAnimatedRainbow  period=60", 2),
    #(
      gspark_widget.SparkAnimated([
        style.Rgb(0, 80, 220),
        style.Rgb(80, 220, 80),
        style.Rgb(220, 80, 0),
      ]),
      "SparkAnimated  blu→verde→rosso",
      5,
    ),
    #(gspark_widget.SparkRainbow, "SparkRainbow  (hue statico per colonna)", 8),
    #(
      gspark_widget.SparkGradient([
        style.Rgb(220, 0, 120),
        style.Rgb(255, 140, 0),
        style.Rgb(255, 255, 0),
      ]),
      "SparkGradient  fucsia→arancio→giallo",
      11,
    ),
    #(
      gspark_widget.SparkSolid(style.Rgb(0, 200, 255)),
      "SparkSolid  rgb(0,200,255)",
      14,
    ),
  ]
  let buf =
    list.fold(fills, buf, fn(b, f) {
      let #(fill, label, dy) = f
      let b2 =
        gspark_widget.render(
          b,
          Rect(Position(rx, area.position.y + dy), Size(rw, 1)),
          gspark_widget.sparkline_new(wave(dy * 4))
            |> gspark_widget.with_fill(fill)
            |> gspark_widget.with_period(60),
          state.anim.frame,
        )
      buffer.set_string(
        b2,
        Position(rx, area.position.y + dy + 1),
        label,
        style.Rgb(150, 150, 150),
        style.Default,
        style.none(),
      )
    })

  // Spinners
  let buf =
    buffer.set_string(
      buf,
      Position(rx, area.position.y + 17),
      text.pad_right("SPINNER WIDGET  (4 stili)", rw),
      style.Default,
      style.Default,
      style.bold(),
    )
  let spinner_row = area.position.y + 18
  let sp_col = int.max(18, rw / 2)
  let spinners = [
    #(gspinner_widget.Dots, "Dots", 0, 0),
    #(gspinner_widget.Line, "Line", sp_col, 0),
    #(gspinner_widget.Circle, "Circle", 0, 1),
    #(gspinner_widget.Bounce, "Bounce", sp_col, 1),
  ]
  let buf =
    list.fold(spinners, buf, fn(b, sp) {
      let #(style_val, label, dx, dy) = sp
      gspinner_widget.render(
        b,
        Rect(Position(rx + dx, spinner_row + dy), Size(18, 1)),
        gspinner_widget.spinner_new()
          |> gspinner_widget.with_style(style_val)
          |> gspinner_widget.with_label(label),
        state.anim.frame,
      )
    })

  let bl = case state.blink_list {
    True -> "blink:∎ ON"
    False -> "blink:□ off"
  }
  buffer.set_string(
    buf,
    Position(rx, area.position.y + ch - 1),
    bl <> "  b=toggle  frame=" <> int.to_string(state.anim.frame),
    style.Default,
    style.Default,
    style.dim(),
  )
}

// ─────────────────────────────────────────────────────────────────
// PAGE: TABELLA, table widget + API reference

fn page_tabella(
  buf: buffer.Buffer,
  area: Rect,
  state: AppState,
) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height
  let tw = int.min(58, w * 2 / 3)
  let rw = int.max(1, w - tw - 1)
  let rx = area.position.x + tw + 1

  let table_area =
    Rect(Position(area.position.x, area.position.y), Size(tw, ch))
  let buf =
    gblock_widget.render(
      buf,
      table_area,
      gblock_widget.block_new()
        |> gblock_widget.with_border(gblock_widget.Single)
        |> gblock_widget.with_title(
          "TABELLA  ↑↓=nav  b=blink",
          gblock_widget.Top,
        ),
    )
  let table_rows = [
    ["Widget", "Modulo", "Anim"],
    ["Lista", "list.gleam", "sì"],
    ["Tabella", "table.gleam", "sì"],
    ["Input", "input.gleam", "no"],
    ["Cursore", "cursor.gleam", "—"],
    ["Progress", "progress.gleam", "sì"],
    ["Gradient", "gradient_bar.gleam", "sì"],
    ["Sparkline", "sparkline.gleam", "sì"],
    ["Marquee", "marquee.gleam", "sì"],
    ["Chart", "chart.gleam", "sì"],
    ["Gauge", "gauge.gleam", "no"],
    ["Block", "block.gleam", "no"],
    ["Paragraph", "paragraph.gleam", "no"],
    ["Spinner", "spinner.gleam", "sì"],
    ["Tabs", "tabs.gleam", "no"],
  ]
  let blink_p = case state.blink_table {
    True -> 6
    False -> 0
  }
  let buf =
    gtable_widget.render_animated(
      buf,
      inner(table_area),
      gtable_widget.table_new(table_rows)
        |> gtable_widget.with_col_widths([12, 22, 5])
        |> gtable_widget.with_blink(blink_p),
      state.table_state,
      state.anim.frame,
    )

  // Right: API reference
  let buf =
    buffer.set_string(
      buf,
      Position(rx, area.position.y),
      text.pad_right("TABLE API", rw),
      style.Default,
      style.Default,
      style.bold(),
    )
  let api_lines = [
    "table_new(rows) → TableWidget",
    "with_col_widths([w1,w2,...])",
    "with_blink(period)",
    "with_header_style(style)",
    "",
    "render_animated(buf, area,",
    "  widget, state, frame)",
    "",
    "state_new() → TableState",
    "select_next_row(state, n)",
    "select_prev_row(state)",
    "",
    "TableState:",
    "  .selected_row  Int",
    "  .offset        Int",
  ]
  let buf =
    list.index_fold(api_lines, buf, fn(b, line, i) {
      buffer.set_string(
        b,
        Position(rx, area.position.y + 2 + i),
        line,
        style.Rgb(180, 220, 255),
        style.Default,
        style.none(),
      )
    })
  let bl = case state.blink_table {
    True -> "blink:∎ ON"
    False -> "blink:□ off"
  }
  buffer.set_string(
    buf,
    Position(rx, area.position.y + ch - 1),
    bl <> "  b=toggle  row=" <> int.to_string(state.table_state.selected_row),
    style.Default,
    style.Default,
    style.dim(),
  )
}

// ─────────────────────────────────────────────────────────────────
// PAGE: RICERCA, input widget + API reference

fn page_ricerca(
  buf: buffer.Buffer,
  area: Rect,
  state: AppState,
) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height
  let iw = int.min(60, w - 4)
  let ix = area.position.x + { w - iw } / 2

  // Input block centered
  let input_area = Rect(Position(ix, area.position.y + 1), Size(iw, 3))
  let buf =
    gblock_widget.render(
      buf,
      input_area,
      gblock_widget.block_new()
        |> gblock_widget.with_border(gblock_widget.Single)
        |> gblock_widget.with_title("RICERCA  digita qui", gblock_widget.Top),
    )
  let buf =
    ginput_widget.render(
      buf,
      Rect(Position(ix + 1, area.position.y + 2), Size(iw - 2, 1)),
      ginput_widget.input_new("digita qui...")
        |> ginput_widget.with_max_length(50),
      state.input_state,
    )

  // Current value display
  let val = state.input_state.value
  let display = case val {
    "" -> "(vuoto)"
    s -> "\"" <> s <> "\""
  }
  let buf =
    buffer.set_string(
      buf,
      Position(ix, area.position.y + 5),
      "valore:  " <> display,
      style.Rgb(180, 255, 180),
      style.Default,
      style.none(),
    )
  let buf =
    buffer.set_string(
      buf,
      Position(ix, area.position.y + 6),
      "cursore: " <> int.to_string(state.input_state.cursor),
      style.Rgb(180, 255, 180),
      style.Default,
      style.none(),
    )
  let buf =
    buffer.set_string(
      buf,
      Position(ix, area.position.y + 7),
      "lunghezza: " <> int.to_string(text.cell_width(val)),
      style.Rgb(180, 255, 180),
      style.Default,
      style.none(),
    )

  // API reference
  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y + 9),
      text.pad_right("INPUT API", w),
      style.Default,
      style.Default,
      style.bold(),
    )
  let api_lines = [
    "input_new(placeholder) → InputWidget",
    "with_max_length(n)     → InputWidget",
    "with_colors(fg, bg)    → InputWidget",
    "",
    "state_new()                    → InputState",
    "state_from_string(s)           → InputState",
    "insert_char(widget, state, ch) → InputState",
    "backspace(state)               → InputState",
    "move_cursor_left(state)        → InputState",
    "move_cursor_right(state)       → InputState",
    "clear_state(state)             → InputState",
    "",
    "InputState:  .value String   .cursor Int",
  ]
  let buf =
    list.index_fold(api_lines, buf, fn(b, line, i) {
      buffer.set_string(
        b,
        Position(area.position.x + 2, area.position.y + 11 + i),
        line,
        style.Rgb(180, 220, 255),
        style.Default,
        style.none(),
      )
    })
  buffer.set_string(
    buf,
    Position(area.position.x, area.position.y + ch - 1),
    "digita=inserisci  ⌫=cancella  TAB=pagina successiva",
    style.Default,
    style.Default,
    style.dim(),
  )
}

// ─────────────────────────────────────────────────────────────────
// PAGE: CURSORI, cursor shapes + DECSCUSR

fn page_cursori(
  buf: buffer.Buffer,
  area: Rect,
  state: AppState,
) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height
  let lw = int.min(42, w / 2)
  let rw = int.max(1, w - lw - 1)
  let rx = area.position.x + lw + 1

  // Left: cursor shapes list
  let left = Rect(Position(area.position.x, area.position.y), Size(lw, ch))
  let buf =
    gblock_widget.render(
      buf,
      left,
      gblock_widget.block_new()
        |> gblock_widget.with_border(gblock_widget.Rounded)
        |> gblock_widget.with_title("CURSORI  ↑↓=seleziona", gblock_widget.Top),
    )
  let shapes = [
    #(0, "Bar blink", style.blink(), "\\e[5 q"),
    #(1, "Bar steady", style.none(), "\\e[6 q"),
    #(2, "Block blink", style.blink(), "\\e[1 q"),
    #(3, "Block steady", style.none(), "\\e[2 q"),
    #(4, "Underline blink", style.blink(), "\\e[3 q"),
    #(5, "Underline steady", style.none(), "\\e[4 q"),
  ]
  let buf =
    list.fold(shapes, buf, fn(b, shape) {
      let #(idx, name, preview_mod, code) = shape
      let is_sel = idx == state.cursor_idx
      let ry = area.position.y + 2 + idx
      let sel_ch = case is_sel {
        True -> "▶ "
        False -> "  "
      }
      let row_mod = case is_sel {
        True -> style.reverse()
        False -> style.none()
      }
      let row_text = text.pad_right(sel_ch <> name <> "  " <> code, lw - 4)
      let b2 =
        buffer.set_string(
          b,
          Position(area.position.x + 2, ry),
          row_text,
          style.Default,
          style.Default,
          row_mod,
        )
      // Preview char at right edge with actual blink modifier
      let prev_fg = case is_sel {
        True -> style.Rgb(255, 220, 0)
        False -> style.Rgb(100, 100, 100)
      }
      buffer.set_string(
        b2,
        Position(area.position.x + lw - 2, ry),
        cursor_shape_preview(idx),
        prev_fg,
        style.Default,
        preview_mod,
      )
    })

  // Right: preview panel
  let right = Rect(Position(rx, area.position.y), Size(rw, ch))
  let buf =
    gblock_widget.render(
      buf,
      right,
      gblock_widget.block_new()
        |> gblock_widget.with_border(gblock_widget.Single)
        |> gblock_widget.with_title("ANTEPRIMA", gblock_widget.Top),
    )
  let cur_name = cursor_shape_name(state.cursor_idx)
  let cur_code = cursor_shape_code(state.cursor_idx)
  let buf =
    buffer.set_string(
      buf,
      Position(rx + 2, area.position.y + 2),
      "Forma attiva:",
      style.Default,
      style.Default,
      style.dim(),
    )
  let buf =
    buffer.set_string(
      buf,
      Position(rx + 2, area.position.y + 3),
      cur_name,
      style.Rgb(255, 220, 0),
      style.Default,
      style.bold(),
    )
  let buf =
    buffer.set_string(
      buf,
      Position(rx + 2, area.position.y + 4),
      "DECSCUSR: " <> cur_code,
      style.Rgb(180, 255, 180),
      style.Default,
      style.none(),
    )
  let buf =
    buffer.set_string(
      buf,
      Position(rx + 2, area.position.y + 6),
      "Il cursore del terminale è posizionato",
      style.Default,
      style.Default,
      style.none(),
    )
  let buf =
    buffer.set_string(
      buf,
      Position(rx + 2, area.position.y + 7),
      "nella lista a sinistra ← sulla riga",
      style.Default,
      style.Default,
      style.none(),
    )
  let buf =
    buffer.set_string(
      buf,
      Position(rx + 2, area.position.y + 8),
      "selezionata. Cambia forma con ↑↓.",
      style.Default,
      style.Default,
      style.none(),
    )
  let buf =
    buffer.set_string(
      buf,
      Position(rx + 2, area.position.y + 10),
      "CURSOR API:",
      style.Default,
      style.Default,
      style.bold(),
    )
  let api = [
    "set_shape(shape) → String",
    "CursorShape variants:",
    "  Block (2)    BlockBlink (1)",
    "  Bar (6)      BarBlink (5)",
    "  Underline(4) UnderlineBlink(3)",
    "",
    "Emette: \\e[N q  (DECSCUSR)",
    "Supporto: dipende dal terminale.",
  ]
  let buf =
    list.index_fold(api, buf, fn(b, line, i) {
      buffer.set_string(
        b,
        Position(rx + 2, area.position.y + 11 + i),
        line,
        style.Rgb(180, 220, 255),
        style.Default,
        style.none(),
      )
    })
  buffer.set_string(
    buf,
    Position(rx + 2, area.position.y + ch - 2),
    "↑↓=seleziona  TAB=pagina successiva",
    style.Default,
    style.Default,
    style.dim(),
  )
}

// ─────────────────────────────────────────────────────────────────
// PAGE: PROGRESS, progress widget + gradient bar widget

fn page_progress(
  buf: buffer.Buffer,
  area: Rect,
  state: AppState,
) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height
  let lab_w = 20
  let bar_x = area.position.x + lab_w
  let bar_w = int.max(1, w - lab_w)
  let pct = state.progress_pct
  let pct_str = int.to_string(pct) <> "%"

  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y),
      text.pad_right(
        "PROGRESS + GRADIENT BAR  valore: " <> pct_str <> "  ↑↓=±10  ←→=±1",
        w,
      ),
      style.Rgb(255, 220, 0),
      style.Default,
      style.bold(),
    )

  // PROGRESS WIDGET section
  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y + 2),
      "── progress widget ──",
      style.Default,
      style.Default,
      style.dim(),
    )
  let prog_rows = [
    #("progress_new", fn(b, y) {
      gprogress_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        gprogress_widget.progress_new(pct)
          |> gprogress_widget.with_label(pct_str),
        state.anim.frame,
      )
    }),
    #("filled_mod Bold", fn(b, y) {
      gprogress_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        gprogress_widget.progress_new(pct)
          |> gprogress_widget.with_label(pct_str)
          |> gprogress_widget.with_filled_modifier(style.bold()),
        state.anim.frame,
      )
    }),
    #("indeterminate", fn(b, y) {
      gprogress_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        gprogress_widget.progress_indeterminate()
          |> gprogress_widget.with_label("caricamento..."),
        state.anim.frame,
      )
    }),
  ]
  let buf =
    list.index_fold(prog_rows, buf, fn(b, row, i) {
      let #(label, render_fn) = row
      let y = area.position.y + 3 + i
      let b2 =
        buffer.set_string(
          b,
          Position(area.position.x, y),
          text.pad_right(label, lab_w),
          style.Rgb(180, 220, 255),
          style.Default,
          style.none(),
        )
      render_fn(b2, y)
    })

  // GRADIENT BAR WIDGET section
  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y + 7),
      "── gradient_bar widget ──",
      style.Default,
      style.Default,
      style.dim(),
    )
  let grad_stops = [
    style.Rgb(0, 100, 220),
    style.Rgb(0, 200, 160),
    style.Rgb(80, 220, 0),
    style.Rgb(230, 180, 0),
    style.Rgb(220, 40, 0),
  ]
  let grad_rows = [
    #("gradient_prog", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggradient_widget.gradient_progress_new(grad_stops, pct),
        state.anim.frame,
      )
    }),
    #("LinearGradient", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggradient_widget.gradient_bar_new(grad_stops)
          |> ggradient_widget.with_percent(pct),
        state.anim.frame,
      )
    }),
    #("AnimatedLinear", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggradient_widget.animated_gradient_bar_new(grad_stops)
          |> ggradient_widget.with_percent(pct)
          |> ggradient_widget.with_period(80),
        state.anim.frame,
      )
    }),
    #("Rainbow", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggradient_widget.rainbow_bar() |> ggradient_widget.with_percent(pct),
        state.anim.frame,
      )
    }),
    #("AnimatedRainbow", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggradient_widget.animated_rainbow_bar()
          |> ggradient_widget.with_percent(pct),
        state.anim.frame,
      )
    }),
    #("Pulse  p=40", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggradient_widget.pulse_bar(style.Rgb(0, 180, 255))
          |> ggradient_widget.with_percent(pct)
          |> ggradient_widget.with_period(40),
        state.anim.frame,
      )
    }),
    #("Pulse cyan p=20", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggradient_widget.pulse_bar(style.Rgb(0, 255, 180))
          |> ggradient_widget.with_percent(pct)
          |> ggradient_widget.with_period(20),
        state.anim.frame,
      )
    }),
    #("Pulse magenta", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggradient_widget.pulse_bar(style.Rgb(220, 0, 180))
          |> ggradient_widget.with_percent(pct)
          |> ggradient_widget.with_period(30),
        state.anim.frame,
      )
    }),
  ]
  let buf =
    list.index_fold(grad_rows, buf, fn(b, row, i) {
      let #(label, render_fn) = row
      let y = area.position.y + 8 + i
      let b2 =
        buffer.set_string(
          b,
          Position(area.position.x, y),
          text.pad_right(label, lab_w),
          style.Rgb(180, 220, 255),
          style.Default,
          style.none(),
        )
      render_fn(b2, y)
    })

  buffer.set_string(
    buf,
    Position(area.position.x, area.position.y + ch - 1),
    text.pad_right(
      "↑↓=±10  ←→=±1  valore=" <> pct_str <> "  TAB=pagina successiva",
      w,
    ),
    style.Default,
    style.Default,
    style.dim(),
  )
}

// ─────────────────────────────────────────────────────────────────
// PAGE: GAUGE, gauge widget showcase

fn page_gauge(
  buf: buffer.Buffer,
  area: Rect,
  state: AppState,
) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height
  let lab_w = 22
  let bar_x = area.position.x + lab_w
  let bar_w = int.max(1, w - lab_w)
  let pct = state.gauge_pct
  let pct_str = int.to_string(pct) <> "%"

  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y),
      text.pad_right(
        "GAUGE WIDGET  valore: " <> pct_str <> "  ↑↓=±10  ←→=±1",
        w,
      ),
      style.Rgb(255, 220, 0),
      style.Default,
      style.bold(),
    )
  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y + 1),
      text.pad_right("──────────────────────────────────", w),
      style.Default,
      style.Default,
      style.dim(),
    )

  let gauge_rows = [
    #("gauge_new", fn(b, y) {
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(pct),
      )
    }),
    #("with_label(pct%)", fn(b, y) {
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(pct) |> ggauge_widget.with_label(pct_str),
      )
    }),
    #("chars ▓░", fn(b, y) {
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(pct)
          |> ggauge_widget.with_chars("▓", "░")
          |> ggauge_widget.with_label(pct_str),
      )
    }),
    #("chars ▪ ·", fn(b, y) {
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(pct)
          |> ggauge_widget.with_chars("▪", "·")
          |> ggauge_widget.with_label(pct_str),
      )
    }),
    #("chars ━ ─", fn(b, y) {
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(pct)
          |> ggauge_widget.with_chars("━", "─")
          |> ggauge_widget.with_label(pct_str),
      )
    }),
    #("color rgb(0,180,255)", fn(b, y) {
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(pct)
          |> ggauge_widget.with_colors(style.Rgb(0, 180, 255), style.Default)
          |> ggauge_widget.with_label(pct_str),
      )
    }),
    #("color gold + label", fn(b, y) {
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(pct)
          |> ggauge_widget.with_colors(style.Rgb(255, 220, 0), style.Default)
          |> ggauge_widget.with_label("GOLD " <> pct_str),
      )
    }),
    #("modifier Bold", fn(b, y) {
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(pct)
          |> ggauge_widget.with_filled_modifier(style.bold())
          |> ggauge_widget.with_label(pct_str),
      )
    }),
    #("animated (osc.)", fn(b, y) {
      let anim_pct = anim.oscillate(10, 100, state.anim.frame, 120)
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(anim_pct)
          |> ggauge_widget.with_label(int.to_string(anim_pct) <> "% (animato)"),
      )
    }),
    #("0%  (empty)", fn(b, y) {
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(0) |> ggauge_widget.with_label("0%"),
      )
    }),
    #("100%  (full)", fn(b, y) {
      ggauge_widget.render(
        b,
        Rect(Position(bar_x, y), Size(bar_w, 1)),
        ggauge_widget.gauge_new(100) |> ggauge_widget.with_label("100%"),
      )
    }),
  ]
  let buf =
    list.index_fold(gauge_rows, buf, fn(b, row, i) {
      let #(label, render_fn) = row
      case i >= ch - 3 {
        True -> b
        False -> {
          let y = area.position.y + 2 + i
          let b2 =
            buffer.set_string(
              b,
              Position(area.position.x, y),
              text.pad_right(label, lab_w),
              style.Rgb(180, 220, 255),
              style.Default,
              style.none(),
            )
          render_fn(b2, y)
        }
      }
    })

  buffer.set_string(
    buf,
    Position(area.position.x, area.position.y + ch - 1),
    text.pad_right(
      "↑↓=±10  ←→=±1  valore=" <> pct_str <> "  TAB=pagina successiva",
      w,
    ),
    style.Default,
    style.Default,
    style.dim(),
  )
}

// ─────────────────────────────────────────────────────────────────
// PAGE: CHART, bar chart widget, fill cycling

fn page_chart(
  buf: buffer.Buffer,
  area: Rect,
  state: AppState,
) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height
  let info_w = 30
  let chart_w = int.max(1, w - info_w - 1)
  let ix = area.position.x + chart_w + 1

  // Chart area (left/center)
  let chart_bars = int.max(1, chart_w / 3)
  let chart_data =
    range(0, chart_bars)
    |> list.map(fn(i) { anim.oscillate(5, 100, state.anim.frame + i * 11, 70) })
  let fill = chart_fill_for_idx(state.chart_fill_idx)
  let buf =
    gchart_widget.render(
      buf,
      Rect(
        Position(area.position.x, area.position.y + 1),
        Size(chart_w, ch - 2),
      ),
      gchart_widget.chart_new(chart_data)
        |> gchart_widget.with_fill(fill)
        |> gchart_widget.with_bar_width(3)
        |> gchart_widget.with_gap(0)
        |> gchart_widget.with_period(70),
      state.anim.frame,
    )

  // Title above chart
  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y),
      text.pad_right(
        "CHART  fill: " <> chart_fill_name(state.chart_fill_idx),
        chart_w,
      ),
      style.Rgb(255, 220, 0),
      style.Default,
      style.bold(),
    )

  // Info panel (right)
  let info_area = Rect(Position(ix, area.position.y), Size(info_w, ch))
  let buf =
    gblock_widget.render(
      buf,
      info_area,
      gblock_widget.block_new()
        |> gblock_widget.with_border(gblock_widget.Single)
        |> gblock_widget.with_title("CHART API", gblock_widget.Top),
    )
  let fill_names = [
    "0 AnimatedRainbow ←",
    "1 Rainbow",
    "2 ChartGradient",
    "3 ChartVertGradient",
    "4 ChartSolid",
  ]
  let buf =
    buffer.set_string(
      buf,
      Position(ix + 1, area.position.y + 2),
      "ChartFill varianti:",
      style.Default,
      style.Default,
      style.bold(),
    )
  let buf =
    list.index_fold(fill_names, buf, fn(b, name, i) {
      let is_active = i == state.chart_fill_idx
      let mod = case is_active {
        True -> style.reverse()
        False -> style.none()
      }
      let fg = case is_active {
        True -> style.Default
        False -> style.Rgb(180, 180, 180)
      }
      buffer.set_string(
        b,
        Position(ix + 1, area.position.y + 3 + i),
        text.pad_right(name, info_w - 2),
        fg,
        style.Default,
        mod,
      )
    })
  let api = [
    "",
    "chart_new(data)",
    "with_fill(ChartFill)",
    "with_bar_width(n)",
    "with_gap(n)",
    "with_max(n)",
    "with_period(n)",
    "",
    "render(buf,area,",
    "  chart,frame)",
  ]
  let buf =
    list.index_fold(api, buf, fn(b, line, i) {
      buffer.set_string(
        b,
        Position(ix + 1, area.position.y + 9 + i),
        line,
        style.Rgb(180, 220, 255),
        style.Default,
        style.none(),
      )
    })
  buffer.set_string(
    buf,
    Position(ix + 1, area.position.y + ch - 2),
    "↑↓=cambia fill",
    style.Default,
    style.Default,
    style.dim(),
  )
}

fn chart_fill_for_idx(idx: Int) -> gchart_widget.ChartFill {
  case idx {
    0 -> gchart_widget.ChartAnimatedRainbow
    1 -> gchart_widget.ChartRainbow
    2 ->
      gchart_widget.ChartGradient([
        style.Rgb(0, 100, 220),
        style.Rgb(80, 220, 0),
        style.Rgb(220, 40, 0),
      ])
    3 ->
      gchart_widget.ChartVerticalGradient([
        style.Rgb(0, 80, 220),
        style.Rgb(220, 40, 0),
      ])
    _ ->
      gchart_widget.ChartSolid([
        style.Rgb(255, 220, 0),
        style.Rgb(0, 200, 255),
        style.Rgb(220, 0, 120),
      ])
  }
}

fn chart_fill_name(idx: Int) -> String {
  case idx {
    0 -> "AnimatedRainbow"
    1 -> "Rainbow"
    2 -> "ChartGradient"
    3 -> "ChartVerticalGradient"
    _ -> "ChartSolid (3 colori)"
  }
}

// ─────────────────────────────────────────────────────────────────
// PAGE: ANIMAZIONI, marquee + rainbow bars + spinners + blink demo

fn page_animazioni(
  buf: buffer.Buffer,
  area: Rect,
  state: AppState,
) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height

  // Section: MARQUEE
  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y),
      text.pad_right("MARQUEE WIDGET  (3 varianti)", w),
      style.Default,
      style.Default,
      style.bold(),
    )
  let marquee_text =
    "etui ✦ sparkline ✦ marquee ✦ gradient ✦ rainbow ✦ pulse ✦ progress ✦ spinner ✦ cursori ✦ liste ✦ tabelle ✦ input"
  let buf =
    gmarquee_widget.render(
      buf,
      Rect(Position(area.position.x, area.position.y + 1), Size(w, 1)),
      gmarquee_widget.marquee_new(marquee_text)
        |> gmarquee_widget.with_speed(4)
        |> gmarquee_widget.with_separator("   ◆   ")
        |> gmarquee_widget.with_style(
          style.Rgb(255, 220, 0),
          style.Default,
          style.bold(),
        ),
      state.anim.frame,
    )
  let buf =
    gmarquee_widget.render(
      buf,
      Rect(Position(area.position.x, area.position.y + 2), Size(w, 1)),
      gmarquee_widget.marquee_new(marquee_text)
        |> gmarquee_widget.with_speed(8)
        |> gmarquee_widget.with_separator(" ── ")
        |> gmarquee_widget.with_style(
          style.Rgb(0, 200, 255),
          style.Default,
          style.none(),
        ),
      state.anim.frame,
    )
  let buf =
    gmarquee_widget.render(
      buf,
      Rect(Position(area.position.x, area.position.y + 3), Size(w, 1)),
      gmarquee_widget.marquee_new("FAST ★ " <> marquee_text)
        |> gmarquee_widget.with_speed(1)
        |> gmarquee_widget.with_separator(" ★ ")
        |> gmarquee_widget.with_style(
          style.Rgb(220, 80, 220),
          style.Default,
          style.none(),
        ),
      state.anim.frame,
    )

  // Section: GRADIENT BAR showcase
  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y + 5),
      text.pad_right("GRADIENT BAR  (full width, animati)", w),
      style.Default,
      style.Default,
      style.bold(),
    )
  let grad_stops = [
    style.Rgb(0, 100, 220),
    style.Rgb(0, 200, 160),
    style.Rgb(80, 220, 0),
    style.Rgb(230, 180, 0),
    style.Rgb(220, 40, 0),
  ]
  let anim_bars = [
    #("AnimatedRainbow", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(area.position.x, y), Size(w, 1)),
        ggradient_widget.animated_rainbow_bar(),
        state.anim.frame,
      )
    }),
    #("AnimatedLinear  p=80", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(area.position.x, y), Size(w, 1)),
        ggradient_widget.animated_gradient_bar_new(grad_stops)
          |> ggradient_widget.with_period(80),
        state.anim.frame,
      )
    }),
    #("Pulse(0,180,255) p=40", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(area.position.x, y), Size(w, 1)),
        ggradient_widget.pulse_bar(style.Rgb(0, 180, 255))
          |> ggradient_widget.with_period(40),
        state.anim.frame,
      )
    }),
    #("Pulse(220,0,180) p=25", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(area.position.x, y), Size(w, 1)),
        ggradient_widget.pulse_bar(style.Rgb(220, 0, 180))
          |> ggradient_widget.with_period(25),
        state.anim.frame,
      )
    }),
    #("LinearGradient (static)", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(area.position.x, y), Size(w, 1)),
        ggradient_widget.gradient_bar_new(grad_stops),
        state.anim.frame,
      )
    }),
    #("Rainbow (static)", fn(b, y) {
      ggradient_widget.render(
        b,
        Rect(Position(area.position.x, y), Size(w, 1)),
        ggradient_widget.rainbow_bar(),
        state.anim.frame,
      )
    }),
  ]
  let buf =
    list.index_fold(anim_bars, buf, fn(b, row, i) {
      let #(label, render_fn) = row
      let base_y = area.position.y + 6 + i * 2
      case base_y + 1 >= area.position.y + ch - 2 {
        True -> b
        False -> {
          let b2 = render_fn(b, base_y)
          buffer.set_string(
            b2,
            Position(area.position.x, base_y + 1),
            label,
            style.Rgb(150, 150, 150),
            style.Default,
            style.none(),
          )
        }
      }
    })

  // Section: style modifiers demo
  let mod_y = area.position.y + ch - 4
  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, mod_y),
      text.pad_right("STYLE MODIFIERS", w),
      style.Default,
      style.Default,
      style.bold(),
    )
  let mod_demos = [
    #("Normal", style.none()),
    #(" Bold ", style.bold()),
    #(" Dim  ", style.dim()),
    #(" Blink", style.blink()),
    #("Reverse", style.reverse()),
    #("RevBlink", style.add(style.reverse(), style.blink())),
    #("BoldRev", style.add(style.bold(), style.reverse())),
  ]
  let buf =
    list.index_fold(mod_demos, buf, fn(b, demo, i) {
      let #(label, mod) = demo
      buffer.set_string(
        b,
        Position(area.position.x + i * 12, mod_y + 1),
        " " <> label <> " ",
        style.Default,
        style.Default,
        mod,
      )
    })

  buffer.set_string(
    buf,
    Position(area.position.x, area.position.y + ch - 1),
    text.pad_right(
      "frame="
        <> int.to_string(state.anim.frame)
        <> "  TAB=pagina successiva  q=quit",
      w,
    ),
    style.Default,
    style.Default,
    style.dim(),
  )
}

// ─────────────────────────────────────────────────────────────────
// PAGE: HBAR, horizontal bar chart, 4 fill variants

fn page_hbar(buf: buffer.Buffer, area: Rect, state: AppState) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height
  let info_w = int.min(30, w / 4)
  let chart_w = int.max(1, w - info_w - 1)
  let ix = area.position.x + chart_w + 1

  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y),
      text.pad_right("HBAR WIDGET  (4 varianti fill)", chart_w),
      style.Rgb(255, 220, 0),
      style.Default,
      style.bold(),
    )

  // Dynamic data per panel (different phase so bars move differently)
  let items = fn(phase) {
    let f = state.anim.frame
    [
      ghbar_widget.item("cpu0", anim.oscillate(10, 100, f + phase, 80)),
      ghbar_widget.item("cpu1", anim.oscillate(5, 90, f + phase + 10, 65)),
      ghbar_widget.item("cpu2", anim.oscillate(20, 80, f + phase + 20, 70)),
      ghbar_widget.item("mem ", anim.oscillate(40, 95, f + phase + 5, 120)),
      ghbar_widget.item("disk", anim.oscillate(15, 60, f + phase + 15, 200)),
    ]
  }

  let panel_h = int.max(2, { ch - 2 } / 4)
  let variants = [
    #("HBarAnimatedRainbow", fn(b, y, h) {
      ghbar_widget.render(
        b,
        Rect(Position(area.position.x, y), Size(chart_w, h)),
        ghbar_widget.hbar_new(items(0))
          |> ghbar_widget.with_fill(ghbar_widget.HBarAnimatedRainbow)
          |> ghbar_widget.with_period(80),
        state.anim.frame,
      )
    }),
    #("HBarRainbow", fn(b, y, h) {
      ghbar_widget.render(
        b,
        Rect(Position(area.position.x, y), Size(chart_w, h)),
        ghbar_widget.hbar_new(items(20))
          |> ghbar_widget.with_fill(ghbar_widget.HBarRainbow),
        state.anim.frame,
      )
    }),
    #("HBarGradient  blu→verde→rosso", fn(b, y, h) {
      ghbar_widget.render(
        b,
        Rect(Position(area.position.x, y), Size(chart_w, h)),
        ghbar_widget.hbar_new(items(40))
          |> ghbar_widget.with_fill(
            ghbar_widget.HBarGradient([
              style.Rgb(0, 80, 220),
              style.Rgb(0, 220, 140),
              style.Rgb(220, 80, 0),
            ]),
          ),
        state.anim.frame,
      )
    }),
    #("HBarSolid  giallo/ciano/magenta", fn(b, y, h) {
      ghbar_widget.render(
        b,
        Rect(Position(area.position.x, y), Size(chart_w, h)),
        ghbar_widget.hbar_new(items(60))
          |> ghbar_widget.with_fill(
            ghbar_widget.HBarSolid([
              style.Rgb(255, 220, 0),
              style.Rgb(0, 200, 255),
              style.Rgb(220, 0, 120),
            ]),
          ),
        state.anim.frame,
      )
    }),
  ]

  let buf =
    list.index_fold(variants, buf, fn(b, v, i) {
      let #(label, render_fn) = v
      let y = area.position.y + 1 + i * panel_h
      case y >= area.position.y + ch - 2 {
        True -> b
        False -> {
          let h = int.min(panel_h - 1, area.position.y + ch - 1 - y - 1)
          let b2 =
            buffer.set_string(
              b,
              Position(area.position.x, y),
              label,
              style.Rgb(180, 220, 255),
              style.Default,
              style.dim(),
            )
          render_fn(b2, y + 1, int.max(1, h))
        }
      }
    })

  // Info panel (right)
  let info_area = Rect(Position(ix, area.position.y), Size(info_w, ch))
  let buf =
    gblock_widget.render(
      buf,
      info_area,
      gblock_widget.block_new()
        |> gblock_widget.with_border(gblock_widget.Single)
        |> gblock_widget.with_title("HBAR API", gblock_widget.Top),
    )
  let api = [
    "hbar_new(items)",
    "item(label, value)",
    "with_fill(HBarFill)",
    "with_max(n)",
    "with_label_width(n)",
    "with_show_value(bool)",
    "with_chars(bar, empty)",
    "with_period(n)",
    "",
    "HBarFill:",
    "  HBarSolid(colors)",
    "  HBarGradient(stops)",
    "  HBarRainbow",
    "  HBarAnimatedRainbow",
    "",
    "render(buf,area,",
    "  hbar,frame)",
  ]
  list.index_fold(api, buf, fn(b, line, i) {
    buffer.set_string(
      b,
      Position(ix + 1, area.position.y + 2 + i),
      line,
      style.Rgb(180, 220, 255),
      style.Default,
      style.none(),
    )
  })
}

// ─────────────────────────────────────────────────────────────────
// PAGE: CANVAS, braille line chart, multi-series

fn page_canvas(
  buf: buffer.Buffer,
  area: Rect,
  state: AppState,
) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height
  let info_w = int.min(28, w / 4)
  let canvas_w = int.max(1, w - info_w - 1)
  let ix = area.position.x + canvas_w + 1
  let canvas_h = int.max(1, ch - 2)
  let n = canvas_w * 2

  let wave = fn(phase, amp_min, amp_max, period) {
    range(0, n)
    |> list.map(fn(x) {
      anim.oscillate(amp_min, amp_max, state.anim.frame + x * 2 + phase, period)
    })
  }

  let series = [
    gcanvas_widget.series_new(wave(0, 10, 90, 60))
      |> gcanvas_widget.with_series_fill(gcanvas_widget.SeriesAnimatedRainbow),
    gcanvas_widget.series_new(wave(30, 20, 80, 45))
      |> gcanvas_widget.with_series_fill(
        gcanvas_widget.SeriesGradient([
          style.Rgb(0, 180, 255),
          style.Rgb(0, 255, 140),
        ]),
      ),
    gcanvas_widget.series_new(wave(60, 5, 50, 35))
      |> gcanvas_widget.with_series_fill(
        gcanvas_widget.SeriesSolid(style.Rgb(255, 120, 0)),
      ),
  ]

  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y),
      text.pad_right(
        "CANVAS WIDGET  braille 2×4 dot grid  risoluzione: "
          <> int.to_string(canvas_w * 2)
          <> "×"
          <> int.to_string(canvas_h * 4)
          <> " pixel",
        canvas_w,
      ),
      style.Rgb(255, 220, 0),
      style.Default,
      style.bold(),
    )

  let buf =
    gcanvas_widget.render(
      buf,
      Rect(
        Position(area.position.x, area.position.y + 1),
        Size(canvas_w, canvas_h),
      ),
      gcanvas_widget.canvas_new(series) |> gcanvas_widget.with_period(60),
      state.anim.frame,
    )

  // Info panel (right)
  let info_area = Rect(Position(ix, area.position.y), Size(info_w, ch))
  let buf =
    gblock_widget.render(
      buf,
      info_area,
      gblock_widget.block_new()
        |> gblock_widget.with_border(gblock_widget.Single)
        |> gblock_widget.with_title("CANVAS API", gblock_widget.Top),
    )
  let legend = [
    "Serie 1:",
    "  SeriesAnimatedRainbow",
    "Serie 2:",
    "  SeriesGradient",
    "  blu→ciano",
    "Serie 3:",
    "  SeriesSolid arancio",
    "",
    "canvas_new(series)",
    "series_new(data)",
    "with_series_fill(f)",
    "with_max(n)",
    "with_bg(color)",
    "with_period(n)",
    "",
    "SeriesFill:",
    "  SeriesSolid(c)",
    "  SeriesGradient(stops)",
    "  SeriesRainbow",
    "  SeriesAnimatedRainbow",
  ]
  list.index_fold(legend, buf, fn(b, line, i) {
    case i >= ch - 3 {
      True -> b
      False ->
        buffer.set_string(
          b,
          Position(ix + 1, area.position.y + 2 + i),
          line,
          style.Rgb(180, 220, 255),
          style.Default,
          style.none(),
        )
    }
  })
}

// ─────────────────────────────────────────────────────────────────
// PAGE: SCENA, sistema solare (braille) + Mandelbrot

fn page_scene(
  buf: buffer.Buffer,
  area: Rect,
  state: AppState,
) -> buffer.Buffer {
  let w = area.size.width
  let ch = area.size.height
  let solar_w = w * 3 / 5
  let mandel_w = int.max(1, w - solar_w - 1)
  let mx = area.position.x + solar_w + 1
  let canvas_h = int.max(1, ch - 1)

  // Titles
  let buf =
    buffer.set_string(
      buf,
      Position(area.position.x, area.position.y),
      text.pad_right(
        "SISTEMA SOLARE  braille "
          <> int.to_string(solar_w * 2)
          <> "×"
          <> int.to_string(canvas_h * 4)
          <> "px",
        solar_w,
      ),
      style.Rgb(255, 220, 0),
      style.Default,
      style.bold(),
    )
  let buf =
    buffer.set_string(
      buf,
      Position(mx, area.position.y),
      text.pad_right("MANDELBROT  iter=20", mandel_w),
      style.Rgb(180, 220, 255),
      style.Default,
      style.bold(),
    )

  // Solar system canvas
  let solar_area =
    Rect(
      Position(area.position.x, area.position.y + 1),
      Size(solar_w, canvas_h),
    )
  let pw = solar_w * 2
  let ph = canvas_h * 4
  let cx = pw / 2
  let cy = ph / 2
  let r1 = int.max(4, pw / 9)
  let r2 = int.max(6, pw / 6)
  let r3 = int.max(8, pw / 4)
  let r4 = int.max(10, pw * 3 / 8)
  let solar_shapes = [
    // Orbit rings (dim)
    gscene_widget.CircleOutline(
      cx,
      cy,
      r1,
      gscene_widget.SceneSolid(style.Rgb(40, 40, 40)),
    ),
    gscene_widget.CircleOutline(
      cx,
      cy,
      r2,
      gscene_widget.SceneSolid(style.Rgb(40, 40, 40)),
    ),
    gscene_widget.CircleOutline(
      cx,
      cy,
      r3,
      gscene_widget.SceneSolid(style.Rgb(40, 40, 40)),
    ),
    gscene_widget.CircleOutline(
      cx,
      cy,
      r4,
      gscene_widget.SceneSolid(style.Rgb(40, 40, 40)),
    ),
    // Sun
    gscene_widget.Disc(
      cx,
      cy,
      5,
      gscene_widget.SceneSolid(style.Rgb(255, 220, 0)),
    ),
    // Mercury, grey, fast
    gscene_widget.Planet(
      cx,
      cy,
      r1,
      2,
      gscene_widget.SceneSolid(style.Rgb(160, 140, 120)),
      38,
    ),
    // Venus, pale gold
    gscene_widget.Planet(
      cx,
      cy,
      r2,
      3,
      gscene_widget.SceneSolid(style.Rgb(220, 190, 120)),
      68,
    ),
    // Earth, blue
    gscene_widget.Planet(
      cx,
      cy,
      r3,
      3,
      gscene_widget.SceneSolid(style.Rgb(60, 140, 255)),
      100,
    ),
    // Mars, red
    gscene_widget.Planet(
      cx,
      cy,
      r4,
      2,
      gscene_widget.SceneSolid(style.Rgb(210, 70, 30)),
      158,
    ),
  ]
  let buf =
    gscene_widget.render(
      buf,
      solar_area,
      gscene_widget.scene_new(solar_shapes),
      state.anim.frame,
    )

  // Mandelbrot canvas
  let mandel_area =
    Rect(Position(mx, area.position.y + 1), Size(mandel_w, canvas_h))
  let buf =
    gscene_widget.render(
      buf,
      mandel_area,
      gscene_widget.scene_new([gscene_widget.Mandelbrot(20)]),
      state.anim.frame,
    )

  buf
}

fn range(start: Int, end: Int) -> List(Int) {
  case start >= end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}
