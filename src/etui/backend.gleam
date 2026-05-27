@target(javascript)
/// Terminal backend abstraction. Two implementations: Erlang + JS/Node.
import gleam/javascript/promise

pub type RenderOp {
  MoveCursor(x: Int, y: Int)
  Write(String)
  ClearScreen
  EnterAltScreen
  ExitAltScreen
  /// Enable SGR mouse tracking (button + scroll events, pixel-precise coords).
  EnableMouse
  /// Disable all mouse tracking.
  DisableMouse
}

/// Mouse button identifier.
pub type MouseButton {
  MouseLeft
  MouseMiddle
  MouseRight
}

pub type InputEvent {
  KeyPress(key: String)
  Resize(width: Int, height: Int)
  Tick
  /// Mouse button pressed. `x`/`y` are 0-based terminal cell coordinates.
  MousePress(x: Int, y: Int, button: MouseButton)
  /// Mouse button released.
  MouseRelease(x: Int, y: Int, button: MouseButton)
  /// Mouse wheel scrolled. `up: True` = scroll up, `False` = scroll down.
  MouseScroll(x: Int, y: Int, up: Bool)
}

pub type TerminalSize {
  TerminalSize(width: Int, height: Int)
}

pub type Backend(state) {
  Backend(
    init: fn() -> Result(state, Error),
    render: fn(state, List(RenderOp)) -> Result(state, Error),
    poll: fn(state, Int) -> Result(#(InputEvent, state), Error),
    next_size: fn(state) -> Result(#(TerminalSize, state), Error),
    cleanup: fn(state) -> Nil,
  )
}

@target(javascript)
pub type AsyncBackend(state) {
  AsyncBackend(
    init: fn() -> Result(state, Error),
    render: fn(state, List(RenderOp)) -> Result(state, Error),
    poll: fn(state, Int) -> promise.Promise(Result(#(InputEvent, state), Error)),
    next_size: fn(state) -> Result(#(TerminalSize, state), Error),
    cleanup: fn(state) -> Nil,
  )
}

pub type Error {
  TerminalUnsupported(reason: String)
  IOError(reason: String)
  Interrupted
}

// ─────────────────────────────────────────────────────────────────
// Protocol operations

pub fn init(backend: Backend(state)) -> Result(state, Error) {
  backend.init()
}

pub fn render(
  backend: Backend(state),
  state: state,
  ops: List(RenderOp),
) -> Result(state, Error) {
  backend.render(state, ops)
}

pub fn poll(
  backend: Backend(state),
  state: state,
  timeout_ms: Int,
) -> Result(#(InputEvent, state), Error) {
  backend.poll(state, timeout_ms)
}

pub fn next_size(
  backend: Backend(state),
  state: state,
) -> Result(#(TerminalSize, state), Error) {
  backend.next_size(state)
}

pub fn cleanup(backend: Backend(state), state: state) -> Nil {
  backend.cleanup(state)
}

// ─────────────────────────────────────────────────────────────────
// Render op utilities

pub fn clear_and_home() -> List(RenderOp) {
  [ClearScreen, MoveCursor(0, 0)]
}
