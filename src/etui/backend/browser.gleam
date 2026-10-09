@target(javascript)
/// Browser (xterm.js) terminal backend for the JavaScript target.
///
/// Provides the same `AsyncBackend` interface as `node.gleam` but uses an
/// xterm.js `Terminal` instance instead of Node's stdin/stdout.
///
/// **Setup:** call `browser_ffi.setup(term)` from JavaScript before calling
/// your app's `main()`. The `priv/components/DinoBrowser.astro` component
/// shows the full wiring.
///
/// Requirements:
/// - Compiled with `gleam build --target javascript`
/// - An xterm.js Terminal attached to the DOM before `main()` runs
///
/// Example (JavaScript side):
/// ```javascript
/// import { Terminal } from "xterm";
/// import { setup } from "./build/dev/javascript/etui/etui/backend/browser_ffi.mjs";
/// import { main } from "./build/dev/javascript/etui/your_app.mjs";
///
/// const term = new Terminal({ cols: 120, rows: 36 });
/// term.open(document.getElementById("terminal"));
/// setup(term);
/// main();
/// ```
import etui/backend.{
  type Error, type InputEvent, type RenderOp, type TerminalSize, ClearScreen,
  EnableMouse, EnterAltScreen, Resize, Tick,
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
pub opaque type BrowserState {
  BrowserState(
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
pub fn blank_state() -> BrowserState {
  BrowserState(cols: 80, rows: 24, pending: "", pending_since: 0, queue: [])
}

// ─────────────────────────────────────────────────────────────────
// Backend construction

@target(javascript)
pub fn new() -> backend.AsyncBackend(BrowserState) {
  backend.AsyncBackend(
    init: init_terminal,
    render: render_ops,
    poll: poll_input,
    next_size: get_terminal_size,
    cleanup: cleanup_terminal,
  )
}

// ─────────────────────────────────────────────────────────────────
// FFI declarations (xterm.js via browser_ffi.mjs)

@target(javascript)
@external(javascript, "./browser_ffi.mjs", "enterRaw")
fn enter_raw_ffi() -> Nil {
  panic as "etui/backend/browser requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./browser_ffi.mjs", "monotonicMs")
fn monotonic_ms_ffi() -> Int {
  panic as "etui/backend/browser requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./browser_ffi.mjs", "exitRaw")
fn exit_raw_ffi() -> Nil {
  panic as "etui/backend/browser requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./browser_ffi.mjs", "writeStdout")
fn write_stdout_ffi(s: String) -> Nil {
  let _ = s
  panic as "etui/backend/browser requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./browser_ffi.mjs", "windowSize")
fn window_size_ffi() -> Result(#(Int, Int), String) {
  panic as "etui/backend/browser requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./browser_ffi.mjs", "readChunk")
fn read_chunk_ffi(timeout_ms: Int) -> promise.Promise(String) {
  let _ = timeout_ms
  panic as "etui/backend/browser requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./browser_ffi.mjs", "takeResize")
fn take_resize_ffi() -> List(Int) {
  panic as "requires the JavaScript target"
}

@target(javascript)
@external(javascript, "./browser_ffi.mjs", "registerCleanup")
fn register_cleanup_ffi(cleanup: fn() -> Nil, restore: String) -> Nil {
  let _ = cleanup
  let _ = restore
  panic as "etui/backend/browser requires the JavaScript target"
}

// ─────────────────────────────────────────────────────────────────
// ANSI sequences (identical to node/erlang backends)

// ─────────────────────────────────────────────────────────────────
// Implementation

@target(javascript)
fn init_terminal() -> Result(BrowserState, Error) {
  enter_raw_ffi()
  let ops = [EnterAltScreen, ClearScreen, EnableMouse]
  let ansi = backend.ops_to_ansi(ops)
  write_stdout_ffi(ansi)
  let #(cols, rows) = case window_size_ffi() {
    Ok(#(c, r)) -> #(c, r)
    Error(_) -> #(80, 24)
  }
  let state =
    BrowserState(
      cols: cols,
      rows: rows,
      pending: "",
      pending_since: 0,
      queue: [],
    )
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
  state: BrowserState,
  ops: List(RenderOp),
) -> Result(BrowserState, Error) {
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
  state: BrowserState,
  timeout_ms: Int,
) -> promise.Promise(Result(#(InputEvent, BrowserState), Error)) {
  case state.queue {
    [event, ..rest] ->
      promise.resolve(Ok(#(event, BrowserState(..state, queue: rest))))
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
          [cols, rows] -> #(BrowserState(..state, cols: cols, rows: rows), [
            Resize(cols, rows),
          ])
          _ -> #(state, [])
        }
        let next =
          BrowserState(
            ..sized,
            pending: pending,
            pending_since: since,
            queue: [],
          )
        case list.append(resize, events) {
          [] -> Ok(#(Tick, next))
          [event, ..rest] -> Ok(#(event, BrowserState(..next, queue: rest)))
        }
      })
    }
  }
}

@target(javascript)
fn get_terminal_size(
  state: BrowserState,
) -> Result(#(TerminalSize, BrowserState), Error) {
  let #(cols, rows) = case window_size_ffi() {
    Ok(#(c, r)) -> #(c, r)
    Error(_) -> #(state.cols, state.rows)
  }
  Ok(#(
    backend.TerminalSize(width: cols, height: rows),
    BrowserState(
      cols: cols,
      rows: rows,
      pending: "",
      pending_since: 0,
      queue: [],
    ),
  ))
}

@target(javascript)
fn cleanup_terminal(state: BrowserState) -> Nil {
  // The whole restore sequence, not just the two modes this backend happens
  // to turn on: an app that enabled bracketed paste or hid the cursor used to
  // leave both that way.
  write_stdout_ffi(backend.restore_sequence())
  exit_raw_ffi()
  let _ = state
  Nil
}
