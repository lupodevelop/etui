@target(erlang)
/// The poll timeout is chosen from the current state before each poll.
import etui/app
@target(erlang)
import etui/backend
@target(erlang)
import gleam/int
@target(erlang)
import gleam/list
@target(erlang)
import gleeunit/should

// The mock reports the timeout it was polled with as a key press, so the
// model ends up holding every timeout the loop asked for, in order.
@target(erlang)
fn echo_timeout() -> backend.Backend(Nil) {
  backend.Backend(
    init: fn() { Ok(Nil) },
    render: fn(s, _ops) { Ok(s) },
    poll: fn(s, timeout) { Ok(#(backend.KeyPress(int.to_string(timeout)), s)) },
    next_size: fn(s) { Ok(#(backend.TerminalSize(80, 24), s)) },
    cleanup: fn(_s) { Nil },
  )
}

@target(erlang)
pub fn timeout_follows_state_test() {
  let result =
    app.run(
      echo_timeout(),
      [],
      fn(_) { [] },
      fn(ev, seen) {
        case ev {
          backend.KeyPress(k) -> [k, ..seen]
          _ -> seen
        }
      },
      fn(seen) { list.length(seen) >= 3 },
      fn(seen) { 10 + list.length(seen) },
    )
  case result {
    app.Success(seen) -> seen |> should.equal(["12", "11", "10"])
    _ -> panic as "loop did not succeed"
  }
}
