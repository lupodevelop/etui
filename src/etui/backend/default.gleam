/// Auto-selects the correct backend for the current compile target.
///
/// Use this in demos and apps instead of importing `erlang` or `node` directly.
/// The library picks the right implementation at compile time.
///
/// ```gleam
/// import etui/app
/// import etui/backend/default
///
/// pub fn main() {
///   let _ = app.run_animated(default.new(), model, render, update, quit, 16)
/// }
/// ```
import etui/backend

@target(erlang)
import etui/backend/erlang

@target(javascript)
import etui/backend/node

@target(erlang)
pub fn new() -> backend.Backend(erlang.ErlangTerminalState) {
  erlang.new()
}

@target(erlang)
pub fn new_with_mouse() -> backend.Backend(erlang.ErlangTerminalState) {
  erlang.new_with_mouse()
}

@target(javascript)
pub fn new() -> backend.AsyncBackend(node.NodeState) {
  node.new()
}

@target(javascript)
pub fn new_with_mouse() -> backend.AsyncBackend(node.NodeState) {
  node.new()
}
