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
///   app.run(node.new(), initial_model, view, update, quit_fn, fn(_) { 16 })
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
  EnableBracketedPaste, EnableMouse, EnterAltScreen, Resize, Tick,
}
@target(javascript)
import etui/backend/pending_input

@target(javascript)
import gleam/javascript/promise

@target(javascript)
import gleam/list

// ─────────────────────────────────────────────────────────────────
// Types

@target(javascript)
pub opaque type NodeState {
  NodeState(
    cols: Int,
    rows: Int,
    /// Bytes read but not yet forming a complete escape sequence.
    pending: String,
    /// Clock reading when `pending` was last added to, see `pending_input`.
    pending_since: Int,
    /// Events decoded but not yet handed to the app.
    queue: List(InputEvent),
  )
}

@target(javascript)
/// A state with nothing read yet, for tests of the backend's own functions.
@internal
pub fn blank_state() -> NodeState {
  NodeState(cols: 80, rows: 24, pending: "", pending_since: 0, queue: [])
}

// ─────────────────────────────────────────────────────────────────
// Backend construction

@target(javascript)
pub fn new() -> backend.AsyncBackend(NodeState) {
  new_with_options(backend.default_options())
}

@target(javascript)
/// Backend with an explicit feature set, matching the Erlang one.
pub fn new_with_options(
  opts: backend.Options,
) -> backend.AsyncBackend(NodeState) {
  backend.AsyncBackend(
    init: fn() { init_terminal(opts) },
    render: render_ops,
    poll: poll_input,
    next_size: get_terminal_size,
    cleanup: cleanup_terminal,
  )
}

@target(javascript)
fn append_if(ops: List(RenderOp), cond: Bool, op: RenderOp) -> List(RenderOp) {
  case cond {
    True -> list.append(ops, [op])
    False -> ops
  }
}

// ─────────────────────────────────────────────────────────────────
// FFI declarations (Node.js ESM)

@target(javascript)
@external(javascript, "./node_ffi.mjs", "enterRaw")
fn enter_raw_ffi() -> Nil {
  panic as "etui/backend/node requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./node_ffi.mjs", "monotonicMs")
fn monotonic_ms_ffi() -> Int {
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
@external(javascript, "./node_ffi.mjs", "readChunk")
fn read_chunk_ffi(timeout_ms: Int) -> promise.Promise(String) {
  let _ = timeout_ms
  panic as "etui/backend/node requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./node_ffi.mjs", "takeResize")
fn take_resize_ffi() -> List(Int) {
  panic as "requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./node_ffi.mjs", "registerCleanup")
fn register_cleanup_ffi(cleanup: fn() -> Nil, restore: String) -> Nil {
  let _ = cleanup
  let _ = restore
  panic as "etui/backend/node requires the JavaScript target"
}

// ─────────────────────────────────────────────────────────────────
// ANSI sequences (same as erlang backend)

// ─────────────────────────────────────────────────────────────────
// Implementation

@target(javascript)
fn init_terminal(opts: backend.Options) -> Result(NodeState, Error) {
  enter_raw_ffi()
  let ops =
    [EnterAltScreen, ClearScreen]
    |> append_if(opts.mouse, EnableMouse)
    |> append_if(opts.paste, EnableBracketedPaste)
  let ansi = backend.ops_to_ansi(ops)
  write_stdout_ffi(ansi)
  let #(cols, rows) = case window_size_ffi() {
    Ok(#(c, r)) -> #(c, r)
    Error(_) -> #(80, 24)
  }
  let state =
    NodeState(cols: cols, rows: rows, pending: "", pending_since: 0, queue: [])
  register_cleanup_ffi(
    fn() {
      let _ = cleanup_terminal(state)
      Nil
    },
    backend.restore_sequence(),
  )
  Ok(state)
}

@target(javascript)
fn render_ops(
  state: NodeState,
  ops: List(RenderOp),
) -> Result(NodeState, Error) {
  let ansi = backend.ops_to_ansi(ops)
  write_stdout_ffi(ansi)
  Ok(state)
}

@target(javascript)
/// Return the next input event.
///
/// One read can carry several key presses, or stop in the middle of an escape
/// sequence. The chunk is decoded by `etui/input`, the same parser the Erlang
/// backend uses, into a queue that is handed out one event per call. The
/// parsing used to live in JavaScript in the FFI, which is why this target
/// spent a release without modified keys, bracketed paste or mouse drags.
fn poll_input(
  state: NodeState,
  timeout_ms: Int,
) -> promise.Promise(Result(#(InputEvent, NodeState), Error)) {
  case state.queue {
    [event, ..rest] ->
      promise.resolve(Ok(#(event, NodeState(..state, queue: rest))))
    [] -> {
      let wait =
        pending_input.read_wait(
          state.pending,
          state.pending_since,
          monotonic_ms_ffi(),
          timeout_ms,
        )
      promise.map(read_chunk_ffi(wait), fn(chunk) {
        let #(events, pending, since) =
          pending_input.decode(
            state.pending,
            state.pending_since,
            chunk,
            monotonic_ms_ffi(),
          )
        let #(sized, resize) = case take_resize_ffi() {
          [cols, rows] -> #(NodeState(..state, cols: cols, rows: rows), [
            Resize(cols, rows),
          ])
          _ -> #(state, [])
        }
        let next =
          NodeState(..sized, pending: pending, pending_since: since, queue: [])
        case list.append(resize, events) {
          [] -> Ok(#(Tick, next))
          [event, ..rest] -> Ok(#(event, NodeState(..next, queue: rest)))
        }
      })
    }
  }
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
    NodeState(cols: cols, rows: rows, pending: "", pending_since: 0, queue: []),
  ))
}

@target(javascript)
fn cleanup_terminal(state: NodeState) -> Nil {
  // The whole restore sequence, not just the two modes this backend happens
  // to turn on: an app that enabled bracketed paste or hid the cursor used to
  // leave both that way.
  write_stdout_ffi(backend.restore_sequence())
  exit_raw_ffi()
  let _ = state
  Nil
}
