/// Terminal backend abstraction. Two implementations: Erlang + JS/Node.
import gleam/int
import gleam/list

@target(javascript)
import gleam/javascript/promise

pub type RenderOp {
  MoveCursor(x: Int, y: Int)
  Write(String)
  ClearScreen
  EnterAltScreen
  ExitAltScreen
  /// Enable SGR mouse tracking (button, drag and scroll events).
  EnableMouse
  /// Disable all mouse tracking.
  DisableMouse
  /// Enable bracketed paste, so pasted text arrives as one `Paste` event
  /// instead of as one key press per character.
  EnableBracketedPaste
  /// Disable bracketed paste.
  DisableBracketedPaste
  /// Start synchronized output (DEC private mode 2026).
  ///
  /// A frame reaches the terminal as a run of cursor moves and text, and an
  /// emulator may paint whatever has arrived so far, which shows half of the
  /// old frame above half of the new one. Between this and
  /// `EndSynchronizedOutput` the emulator keeps showing what it had and
  /// applies everything that was written in one go.
  BeginSynchronizedOutput
  /// Show what was written since `BeginSynchronizedOutput`.
  EndSynchronizedOutput
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
  /// Mouse moved with a button held down.
  MouseDrag(x: Int, y: Int, button: MouseButton)
  /// Mouse moved with no button held. Only reported when the backend enables
  /// motion tracking.
  MouseMove(x: Int, y: Int)
  /// Text pasted via bracketed paste, delivered as one event rather than as
  /// hundreds of key presses. Requires a backend that enables bracketed paste.
  Paste(text: String)
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

/// What a backend should turn on when it initialises the terminal.
pub type Options {
  Options(
    /// Report mouse buttons, drags and the wheel as input events.
    mouse: Bool,
    /// Deliver pasted text as one `Paste` event.
    ///
    /// Off by default: with it on, an app that does not handle `Paste` sees
    /// nothing at all when the user pastes, which is worse than the mangled
    /// key presses it sees today.
    paste: Bool,
  )
}

/// Mouse off, bracketed paste off.
pub fn default_options() -> Options {
  Options(mouse: False, paste: False)
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

/// The escape sequence for one render op.
///
/// One table, not one per backend. The three backends each carried a copy,
/// and the copies had already drifted: `EnableMouse` asked for click
/// tracking (1000) on the JavaScript targets and not on Erlang, so the same
/// program reported subtly different mouse events depending on where it ran.
pub fn op_to_ansi(op: RenderOp) -> String {
  case op {
    Write(s) -> s
    MoveCursor(x, y) ->
      "\u{001B}[" <> int.to_string(y + 1) <> ";" <> int.to_string(x + 1) <> "H"
    ClearScreen -> "\u{001B}[2J\u{001B}[H"
    EnterAltScreen -> "\u{001B}[?1049h"
    ExitAltScreen -> "\u{001B}[?1049l"
    // Button-event tracking (1002) rather than plain click tracking (1000):
    // it reports motion while a button is held, which is what makes MouseDrag
    // possible. 1006 is the SGR encoding, which lifts the 223-column limit.
    EnableMouse -> "\u{001B}[?1002h\u{001B}[?1006h"
    // Clear all common xterm mouse/alt-scroll modes so the shell does not
    // inherit wheel or click reporting after the app exits.
    DisableMouse ->
      "\u{001B}[?1007l\u{001B}[?1015l\u{001B}[?1006l\u{001B}[?1005l\u{001B}[?1003l\u{001B}[?1002l\u{001B}[?1000l"
    EnableBracketedPaste -> "\u{001B}[?2004h"
    DisableBracketedPaste -> "\u{001B}[?2004l"
    // A terminal that does not know mode 2026 ignores it, so these are sent
    // without asking first.
    BeginSynchronizedOutput -> "\u{001B}[?2026h"
    EndSynchronizedOutput -> "\u{001B}[?2026l"
  }
}

/// Concatenated escape sequences for a list of ops.
pub fn ops_to_ansi(ops: List(RenderOp)) -> String {
  list.fold(ops, "", fn(acc, op) { acc <> op_to_ansi(op) })
}

/// Everything an app has to undo before the terminal is someone else's again.
///
/// Unconditional, and in this order on purpose: a cleanup path runs when
/// things have already gone wrong, and asking a terminal to leave a mode it
/// was never in costs nothing, while tracking which modes were entered costs
/// a correct answer exactly when the state is least trustworthy.
pub fn restore_ops() -> List(RenderOp) {
  [
    // First, so that an app which died between the two halves of a frame does
    // not leave the screen held.
    EndSynchronizedOutput,
    DisableMouse,
    DisableBracketedPaste,
    ExitAltScreen,
    // Auto-wrap back on (the alt screen is left with it off), attributes
    // reset, cursor visible. No RenderOp names these: they are not things an
    // app asks for, they are the state a terminal is handed back in.
    Write("\u{001B}[?7h\u{001B}[0m\u{001B}[?25h"),
  ]
}

/// `restore_ops` as the bytes to send.
///
/// The single source for the restore sequence on every target, including the
/// two places that cannot call Gleam: the shell watchdog that fires when the
/// runtime dies without unwinding, and the Node exit handler. Both are handed
/// this string rather than keeping a copy of it.
pub fn restore_sequence() -> String {
  ops_to_ansi(restore_ops())
}
