@target(javascript)
/// The JavaScript backends start and stop without throwing, with or without a
/// terminal behind them. The rest of the suite only runs pure functions, so a
/// missing import in the FFI files went unnoticed until an app ran.
import etui/backend/browser
@target(javascript)
import etui/backend/node

@target(javascript)
pub fn node_cleanup_does_not_throw_test() {
  let b = node.new()
  b.cleanup(node.blank_state())
}

@target(javascript)
pub fn browser_cleanup_does_not_throw_test() {
  let b = browser.new()
  b.cleanup(browser.blank_state())
}

@target(javascript)
pub fn node_starts_and_stops_test() {
  let b = node.new()
  let assert Ok(state) = b.init()
  b.cleanup(state)
}
