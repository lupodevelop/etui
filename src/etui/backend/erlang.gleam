/// Erlang/BEAM terminal backend with true raw mode.
/// Uses native Erlang modules for terminal control (inspired by Etch).
import etui/backend.{
  type Error, type InputEvent, type RenderOp, type TerminalSize, ClearScreen,
  DisableMouse, EnableMouse, EnterAltScreen, ExitAltScreen, IOError, MouseLeft,
  MouseMiddle, MousePress, MouseRelease, MouseRight, MouseScroll, MoveCursor,
  Write,
}
import gleam/int
import gleam/list
import gleam/string

// ─────────────────────────────────────────────────────────────────
// Types

pub type ErlangTerminalState {
  ErlangTerminalState(raw_mode_active: Bool, cols: Int, rows: Int, mouse: Bool)
}

// ─────────────────────────────────────────────────────────────────
// Backend construction

pub fn new() -> backend.Backend(ErlangTerminalState) {
  new_impl(False)
}

pub fn new_with_mouse() -> backend.Backend(ErlangTerminalState) {
  new_impl(True)
}

fn new_impl(mouse: Bool) -> backend.Backend(ErlangTerminalState) {
  backend.Backend(
    init: fn() { init_terminal(mouse) },
    render: render_ops,
    poll: poll_input,
    next_size: get_terminal_size,
    cleanup: cleanup_terminal,
  )
}

// ─────────────────────────────────────────────────────────────────
// FFI declarations (native Erlang)

@external(erlang, "etui_tty_state", "init")
fn init_tty_state() -> Nil {
  panic as "etui/backend/erlang requires the Erlang target"
}

@external(erlang, "etui_tty_state", "set_raw")
fn set_raw_state(is_raw: Bool) -> Nil {
  let _ = is_raw
  panic as "etui/backend/erlang requires the Erlang target"
}

@external(erlang, "etui_terminal_ffi", "enter_raw")
fn enter_raw_ffi() -> Nil {
  panic as "etui/backend/erlang requires the Erlang target"
}

@external(erlang, "etui_terminal_ffi", "exit_raw")
fn exit_raw_ffi() -> Nil {
  panic as "etui/backend/erlang requires the Erlang target"
}

@external(erlang, "etui_terminal_ffi", "window_size")
fn window_size_ffi() -> Result(#(Int, Int), String) {
  panic as "etui/backend/erlang requires the Erlang target"
}

@external(erlang, "io", "put_chars")
fn write_string(s: String) -> Nil {
  let _ = s
  panic as "etui/backend/erlang requires the Erlang target"
}

@external(erlang, "etui_terminal_ffi", "read_with_timeout")
fn read_with_timeout_ffi(timeout_ms: Int) -> Result(String, Nil) {
  let _ = timeout_ms
  panic as "etui/backend/erlang requires the Erlang target"
}

@external(erlang, "etui_terminal_ffi", "install_sigint_cleanup")
fn install_sigint_cleanup_ffi(cleanup: fn() -> Nil) -> Nil {
  let _ = cleanup
  panic as "etui/backend/erlang requires the Erlang target"
}

@external(erlang, "etui_terminal_ffi", "uninstall_sigint_cleanup")
fn uninstall_sigint_cleanup_ffi() -> Nil {
  panic as "etui/backend/erlang requires the Erlang target"
}

@external(erlang, "etui_terminal_ffi", "write_cleanup")
fn write_cleanup_ffi() -> Nil {
  panic as "etui/backend/erlang requires the Erlang target"
}

// ─────────────────────────────────────────────────────────────────
// Implementation

fn init_terminal(mouse: Bool) -> Result(ErlangTerminalState, Error) {
  init_tty_state()
  let init_ops = case mouse {
    True -> [EnterAltScreen, ClearScreen, EnableMouse]
    False -> [EnterAltScreen, ClearScreen]
  }
  case write_ops_to_stdout(init_ops) {
    Ok(Nil) -> {
      enter_raw_ffi()
      set_raw_state(True)
      let #(cols, rows) = case window_size_ffi() {
        Ok(#(c, r)) -> #(c, r)
        Error(_) -> #(80, 24)
      }
      install_sigint_cleanup_ffi(fn() { terminal_cleanup() })
      Ok(ErlangTerminalState(
        raw_mode_active: True,
        cols: cols,
        rows: rows,
        mouse: mouse,
      ))
    }
    Error(reason) -> Error(IOError(reason))
  }
}

fn render_ops(
  state: ErlangTerminalState,
  ops: List(RenderOp),
) -> Result(ErlangTerminalState, Error) {
  case write_ops_to_stdout(ops) {
    Ok(Nil) -> Ok(state)
    Error(reason) -> Error(IOError(reason))
  }
}

fn poll_input(
  state: ErlangTerminalState,
  timeout_ms: Int,
) -> Result(#(InputEvent, ErlangTerminalState), Error) {
  let input_event = case read_with_timeout_ffi(timeout_ms) {
    Ok(input) -> parse_input(input)
    Error(_) -> backend.Tick
  }
  case window_size_ffi() {
    Ok(#(c, r)) ->
      case c == state.cols && r == state.rows {
        True -> Ok(#(input_event, state))
        False ->
          Ok(#(
            backend.Resize(c, r),
            ErlangTerminalState(..state, cols: c, rows: r),
          ))
      }
    Error(_) -> Ok(#(input_event, state))
  }
}

fn get_terminal_size(
  state: ErlangTerminalState,
) -> Result(#(TerminalSize, ErlangTerminalState), Error) {
  case window_size_ffi() {
    Ok(#(w, h)) -> Ok(#(backend.TerminalSize(width: w, height: h), state))
    Error(_) -> Ok(#(backend.TerminalSize(width: 80, height: 24), state))
  }
}

// Shared cleanup: idempotent, safe to call from both normal exit and SIGINT.
// Order matters: write escape sequences BEFORE exit_raw_ffi so the sequences
// reach the terminal while the I/O group leader is still set up correctly.
fn terminal_cleanup() -> Nil {
  uninstall_sigint_cleanup_ffi()
  write_cleanup_ffi()
  exit_raw_ffi()
  set_raw_state(False)
  Nil
}

fn cleanup_terminal(_state: ErlangTerminalState) -> Nil {
  terminal_cleanup()
}

// ─────────────────────────────────────────────────────────────────
// Helpers

fn write_ops_to_stdout(ops: List(RenderOp)) -> Result(Nil, String) {
  let output =
    ops
    |> list.fold("", fn(acc, op) { acc <> render_op_to_string(op) })

  case output {
    "" -> Ok(Nil)
    s -> {
      write_string(s)
      Ok(Nil)
    }
  }
}

fn render_op_to_string(op: RenderOp) -> String {
  case op {
    MoveCursor(x, y) ->
      "\u{001B}[" <> int_to_string(y + 1) <> ";" <> int_to_string(x + 1) <> "H"
    Write(s) -> s
    ClearScreen -> "\u{001B}[2J\u{001B}[H"
    EnterAltScreen -> "\u{001B}[?1049h"
    ExitAltScreen -> "\u{001B}[?1049l"
    // Enable SGR extended mouse tracking (button + scroll events).
    EnableMouse -> "\u{001B}[?1000h\u{001B}[?1006h"
    // Clear all common xterm mouse/alt-scroll modes so the shell does not
    // inherit wheel/click reporting after the app exits.
    DisableMouse ->
      "\u{001B}[?1007l\u{001B}[?1015l\u{001B}[?1006l\u{001B}[?1005l\u{001B}[?1003l\u{001B}[?1002l\u{001B}[?1000l"
  }
}

// Parse a raw terminal input string into an InputEvent.
// Normalises escape sequences to friendly key names so keys.match/1 works.
fn parse_input(input: String) -> InputEvent {
  case input {
    "" -> backend.Tick
    // SGR mouse: \e[<Cb;Cx;CyM (press) or \e[<Cb;Cx;Cym (release)
    _ ->
      case string.starts_with(input, "\u{001B}[<") {
        True -> parse_sgr_mouse(string.drop_start(input, 3))
        False -> backend.KeyPress(normalise_key(input))
      }
  }
}

// Map raw terminal byte sequences to friendly key name strings.
// These match the constants expected by keys.match/1 in keys.gleam.
fn normalise_key(raw: String) -> String {
  case raw {
    // ── Arrow keys ─────────────────────────────────────────────
    "\u{001B}[A" | "\u{001B}OA" -> "up"
    "\u{001B}[B" | "\u{001B}OB" -> "down"
    "\u{001B}[C" | "\u{001B}OC" -> "right"
    "\u{001B}[D" | "\u{001B}OD" -> "left"
    // ── Enter / newline ────────────────────────────────────────
    "\r" | "\n" -> "enter"
    // ── Backspace / Delete ─────────────────────────────────────
    "\u{007F}" | "\u{0008}" -> "backspace"
    "\u{001B}[3~" -> "delete"
    // ── Tab / Shift-Tab ────────────────────────────────────────
    "\t" -> "tab"
    "\u{001B}[Z" -> "backtab"
    // ── Escape (lone) ──────────────────────────────────────────
    "\u{001B}" -> "esc"
    // ── Insert / Page / Home / End ─────────────────────────────
    "\u{001B}[2~" -> "insert"
    "\u{001B}[5~" -> "pageup"
    "\u{001B}[6~" -> "pagedown"
    "\u{001B}[H" | "\u{001B}OH" | "\u{001B}[1~" -> "home"
    "\u{001B}[F" | "\u{001B}OF" | "\u{001B}[4~" -> "end"
    // ── Function keys (xterm VT220 + SS3 variants) ─────────────
    "\u{001B}[11~" | "\u{001B}OP" -> "f1"
    "\u{001B}[12~" | "\u{001B}OQ" -> "f2"
    "\u{001B}[13~" | "\u{001B}OR" -> "f3"
    "\u{001B}[14~" | "\u{001B}OS" -> "f4"
    "\u{001B}[15~" -> "f5"
    "\u{001B}[17~" -> "f6"
    "\u{001B}[18~" -> "f7"
    "\u{001B}[19~" -> "f8"
    "\u{001B}[20~" -> "f9"
    "\u{001B}[21~" -> "f10"
    "\u{001B}[23~" -> "f11"
    "\u{001B}[24~" -> "f12"
    // ── Ctrl+letter: codepoints 0x01–0x1A (a–z) ───────────────
    "\u{0001}" -> "ctrl+a"
    "\u{0002}" -> "ctrl+b"
    "\u{0003}" -> "ctrl+c"
    "\u{0004}" -> "ctrl+d"
    "\u{0005}" -> "ctrl+e"
    "\u{0006}" -> "ctrl+f"
    "\u{0007}" -> "ctrl+g"
    "\u{000B}" -> "ctrl+k"
    "\u{000C}" -> "ctrl+l"
    "\u{000E}" -> "ctrl+n"
    "\u{000F}" -> "ctrl+o"
    "\u{0010}" -> "ctrl+p"
    "\u{0011}" -> "ctrl+q"
    "\u{0012}" -> "ctrl+r"
    "\u{0013}" -> "ctrl+s"
    "\u{0014}" -> "ctrl+t"
    "\u{0015}" -> "ctrl+u"
    "\u{0016}" -> "ctrl+v"
    "\u{0017}" -> "ctrl+w"
    "\u{0018}" -> "ctrl+x"
    "\u{0019}" -> "ctrl+y"
    "\u{001A}" -> "ctrl+z"
    // ── Alt+letter: ESC followed by a single printable char ────
    s ->
      case string.starts_with(s, "\u{001B}") && string.length(s) == 2 {
        True -> "alt+" <> string.drop_start(s, 1)
        False -> s
      }
  }
}

// Parse the payload after "\e[<": "Cb;Cx;CyM" or "Cb;Cx;Cym"
fn parse_sgr_mouse(payload: String) -> InputEvent {
  let is_press = string.ends_with(payload, "M")
  let trimmed = case is_press {
    True -> string.drop_end(payload, 1)
    False -> string.drop_end(payload, 1)
  }
  case string.split(trimmed, ";") {
    [cb_str, cx_str, cy_str] ->
      case int.parse(cb_str), int.parse(cx_str), int.parse(cy_str) {
        Ok(cb), Ok(cx), Ok(cy) -> {
          // Coordinates are 1-based in SGR; convert to 0-based.
          let x = cx - 1
          let y = cy - 1
          case cb {
            // Scroll events (button code 64 = up, 65 = down)
            64 -> MouseScroll(x, y, True)
            65 -> MouseScroll(x, y, False)
            // Button press / release
            _ -> {
              let btn = case cb % 4 {
                0 -> MouseLeft
                1 -> MouseMiddle
                2 -> MouseRight
                _ -> MouseLeft
              }
              case is_press {
                True -> MousePress(x, y, btn)
                False -> MouseRelease(x, y, btn)
              }
            }
          }
        }
        _, _, _ -> backend.KeyPress("\u{001B}[<" <> payload)
      }
    _ -> backend.KeyPress("\u{001B}[<" <> payload)
  }
}

fn int_to_string(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    _ -> {
      let digit = case n % 10 {
        0 -> "0"
        1 -> "1"
        2 -> "2"
        3 -> "3"
        4 -> "4"
        5 -> "5"
        6 -> "6"
        7 -> "7"
        8 -> "8"
        9 -> "9"
        _ -> "?"
      }
      int_to_string(n / 10) <> digit
    }
  }
}
