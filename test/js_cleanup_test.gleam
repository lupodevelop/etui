@target(javascript)
/// Cleanup on the JavaScript backends must not throw, including when no
/// terminal was ever put in raw mode.
import etui/backend/browser
@target(javascript)
import etui/backend/node

@target(javascript)
pub fn node_cleanup_does_not_throw_test() {
  let b = node.new()
  b.cleanup(node.NodeState(cols: 80, rows: 24, pending: "", queue: []))
}

@target(javascript)
pub fn browser_cleanup_does_not_throw_test() {
  let b = browser.new()
  b.cleanup(browser.BrowserState(cols: 80, rows: 24, pending: "", queue: []))
}
