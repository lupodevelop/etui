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
@external(erlang, "etui_fake_console", "with_replies")
fn with_replies_bits(replies: List(BitArray), action: fn() -> a) -> a

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

@target(erlang)
@external(erlang, "erlang", "monotonic_time")
fn monotonic_ms(unit: Unit) -> Int

@target(erlang)
type Unit {
  Millisecond
}

// A lone Escape is a key press after the backend's own short deadline, even
// when the app asks to wait a minute.
@target(erlang)
pub fn a_lone_escape_resolves_without_waiting_the_app_timeout_test() {
  let #(event, elapsed) =
    with_replies_bits([<<27>>], fn() {
      let b = erlang.new()
      let assert Ok(#(first, s1)) = b.poll(erlang.blank_state(), 60_000)
      first |> should.equal(backend.Tick)
      let start = monotonic_ms(Millisecond)
      let assert Ok(#(second, _)) = b.poll(s1, 60_000)
      #(second, monotonic_ms(Millisecond) - start)
    })
  event |> should.equal(backend.KeyPress("esc"))
  { elapsed < 1000 } |> should.equal(True)
}

// A zero-wait poll must keep the first half of a split sequence.
@target(erlang)
pub fn a_zero_wait_poll_keeps_half_a_sequence_test() {
  with_replies_bits([<<27>>], fn() {
    let b = erlang.new()
    let assert Ok(#(_, s1)) = b.poll(erlang.blank_state(), 1000)
    let assert Ok(#(second, _)) = b.poll(s1, 0)
    second |> should.equal(backend.Tick)
  })
}
