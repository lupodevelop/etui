@target(erlang)
import etui/backend
@target(erlang)
import etui/backend/erlang
@target(erlang)
import gleeunit/should

@target(erlang)
type Reply {
  Eof
  Failed
}

@target(erlang)
@external(erlang, "etui_fake_console", "with_replies")
fn with_replies(replies: List(Reply), action: fn() -> a) -> a

@target(erlang)
fn poll_once() {
  erlang.new().poll(erlang.blank_state(), 1000)
}

@target(erlang)
pub fn end_of_input_ends_the_backend_test() {
  with_replies([Eof], poll_once)
  |> should.equal(Error(backend.IOError("terminal input is closed")))
}

@target(erlang)
pub fn a_failed_read_ends_the_backend_test() {
  with_replies([Failed], poll_once)
  |> should.equal(Error(backend.IOError("terminal input is closed")))
}
