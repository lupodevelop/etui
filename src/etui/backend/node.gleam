@target(javascript)
/// Node.js terminal backend for the JavaScript target.
///
/// Provides the same `Backend` interface as `erlang.gleam` but uses
/// Node.js process.stdin/stdout via ESM FFI.
///
/// Requirements:
/// - Node.js >= 16
/// - Running in a TTY (terminal, not a pipe)
/// - Compiled with `gleam build --target javascript`
///
/// Example:
/// ```gleam
/// import etui/app
/// import etui/backend/node
///
/// pub fn main() {
///   app.run(node.new(), initial_model, view, update, quit_fn, 16)
/// }
/// ```
///
/// ## JS target notes
///
/// `app.run` is synchronous on the Erlang target but uses async polling
/// on Node.js. The event loop runs via `setTimeout` in Node's event loop.
/// Each `poll_input` call is async-awaited internally by the FFI layer.
import etui/backend.{
  type Error, type InputEvent, type RenderOp, type TerminalSize, ClearScreen,
  DisableMouse, EnableMouse, EnterAltScreen, ExitAltScreen, IOError, MoveCursor,
  Resize, Write,
}

@target(javascript)
import gleam/int

@target(javascript)
import gleam/javascript/promise

@target(javascript)
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

pub type NodeState {
  NodeState(cols: Int, rows: Int)
}

// ─────────────────────────────────────────────────────────────────
// Backend construction

@target(javascript)
pub fn new() -> backend.AsyncBackend(NodeState) {
  backend.AsyncBackend(
    init: init_terminal,
    render: render_ops,
    poll: poll_input,
    next_size: get_terminal_size,
    cleanup: cleanup_terminal,
  )
}

// ─────────────────────────────────────────────────────────────────
// FFI declarations (Node.js ESM)

@target(javascript)
@external(javascript, "./node_ffi.mjs", "enterRaw")
fn enter_raw_ffi() -> Nil {
  panic as "etui/backend/node requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./node_ffi.mjs", "exitRaw")
fn exit_raw_ffi() -> Nil {
  panic as "etui/backend/node requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./node_ffi.mjs", "writeStdout")
fn write_stdout_ffi(s: String) -> Nil {
  let _ = s
  panic as "etui/backend/node requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./node_ffi.mjs", "windowSize")
fn window_size_ffi() -> Result(#(Int, Int), String) {
  panic as "etui/backend/node requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./node_ffi.mjs", "pollInput")
fn poll_input_ffi(timeout_ms: Int) -> promise.Promise(Result(InputEvent, Nil)) {
  let _ = timeout_ms
  panic as "etui/backend/node requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./node_ffi.mjs", "registerCleanup")
fn register_cleanup_ffi(cleanup: fn() -> Nil) -> Nil {
  let _ = cleanup
  panic as "etui/backend/node requires the JavaScript target"
}

// ─────────────────────────────────────────────────────────────────
// ANSI sequences (same as erlang backend)

@target(javascript)
fn render_op_to_ansi(op: RenderOp) -> String {
  case op {
    Write(s) -> s
    MoveCursor(x, y) ->
      "\u{001B}[" <> int.to_string(y + 1) <> ";" <> int.to_string(x + 1) <> "H"
    ClearScreen -> "\u{001B}[2J\u{001B}[H"
    EnterAltScreen -> "\u{001B}[?1049h"
    ExitAltScreen -> "\u{001B}[?1049l"
    EnableMouse -> "\u{001B}[?1000h\u{001B}[?1002h\u{001B}[?1006h"
    DisableMouse ->
      "\u{001B}[?1007l\u{001B}[?1015l\u{001B}[?1006l\u{001B}[?1005l\u{001B}[?1003l\u{001B}[?1002l\u{001B}[?1000l"
  }
}

// ─────────────────────────────────────────────────────────────────
// Implementation

@target(javascript)
fn init_terminal() -> Result(NodeState, Error) {
  enter_raw_ffi()
  let ops = [EnterAltScreen, ClearScreen, EnableMouse]
  let ansi = list.map(ops, render_op_to_ansi) |> string_join("")
  write_stdout_ffi(ansi)
  let #(cols, rows) = case window_size_ffi() {
    Ok(#(c, r)) -> #(c, r)
    Error(_) -> #(80, 24)
  }
  let state = NodeState(cols: cols, rows: rows)
  register_cleanup_ffi(fn() {
    let _ = cleanup_terminal(state)
    Nil
  })
  Ok(state)
}

@target(javascript)
fn render_ops(
  state: NodeState,
  ops: List(RenderOp),
) -> Result(NodeState, Error) {
  let ansi = list.map(ops, render_op_to_ansi) |> string_join("")
  write_stdout_ffi(ansi)
  Ok(state)
}

@target(javascript)
fn poll_input(
  state: NodeState,
  timeout_ms: Int,
) -> promise.Promise(Result(#(InputEvent, NodeState), Error)) {
  promise.map(poll_input_ffi(timeout_ms), fn(result) {
    case result {
      Ok(ev) -> {
        let new_state = case ev {
          Resize(c, r) -> NodeState(cols: c, rows: r)
          _ -> state
        }
        Ok(#(ev, new_state))
      }
      Error(_) -> Error(IOError("poll failed"))
    }
  })
}

@target(javascript)
fn get_terminal_size(
  state: NodeState,
) -> Result(#(TerminalSize, NodeState), Error) {
  let #(cols, rows) = case window_size_ffi() {
    Ok(#(c, r)) -> #(c, r)
    Error(_) -> #(state.cols, state.rows)
  }
  Ok(#(
    backend.TerminalSize(width: cols, height: rows),
    NodeState(cols: cols, rows: rows),
  ))
}

@target(javascript)
fn cleanup_terminal(state: NodeState) -> Nil {
  let ops = [DisableMouse, ExitAltScreen]
  let ansi = list.map(ops, render_op_to_ansi) |> string_join("")
  write_stdout_ffi(ansi)
  exit_raw_ffi()
  let _ = state
  Nil
}

// ─── String join helper (no stdlib dependency) ───────────────────

@target(javascript)
fn string_join(parts: List(String), sep: String) -> String {
  case parts {
    [] -> ""
    [h] -> h
    [h, ..rest] -> h <> sep <> string_join(rest, sep)
  }
}
