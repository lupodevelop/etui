/// A half-read escape sequence waits for a deadline, not for a read to come
/// back empty.
import etui/backend
import etui/backend/pending_input as p
import gleeunit/should

const esc = "\u{1B}"

pub fn nothing_pending_waits_the_whole_timeout_test() {
  p.read_wait("", 0, 500, 250) |> should.equal(250)
}

pub fn a_pending_escape_caps_the_wait_at_the_deadline_test() {
  p.read_wait(esc, 100, 100, 60_000) |> should.equal(p.escape_deadline_ms)
  p.read_wait(esc, 100, 130, 60_000) |> should.equal(10)
  p.read_wait(esc, 100, 500, 60_000) |> should.equal(0)
}

pub fn a_short_timeout_still_wins_test() {
  p.read_wait(esc, 100, 100, 16) |> should.equal(16)
}

pub fn an_empty_read_before_the_deadline_keeps_the_bytes_test() {
  // A zero-wait poll or a resize wake must not turn "ESC" of "ESC [ A" into a
  // key press.
  p.decode(esc, 100, "", 105) |> should.equal(#([], esc, 100))
}

pub fn an_empty_read_after_the_deadline_is_escape_test() {
  p.decode(esc, 100, "", 140)
  |> should.equal(#([backend.KeyPress("esc")], "", 0))
}

pub fn the_rest_of_a_sequence_completes_it_test() {
  p.decode(esc, 100, "[A", 110)
  |> should.equal(#([backend.KeyPress("up")], "", 110))
}

pub fn more_bytes_restart_the_clock_test() {
  p.decode("", 0, esc, 200) |> should.equal(#([], esc, 200))
  p.decode(esc <> "[1;5", 200, "", 230)
  |> should.equal(#([], esc <> "[1;5", 200))
}

pub fn an_unfinished_paste_outlasts_an_escape_test() {
  let partial = esc <> "[200~hello"
  p.read_wait(partial, 0, 500, 60_000) |> should.equal(500)
  p.decode(partial, 0, "", 500) |> should.equal(#([], partial, 0))
  p.decode(partial, 0, "", 1000)
  |> should.equal(#([backend.KeyPress("esc")], "", 0))
}

pub fn nothing_to_resolve_stays_empty_test() {
  p.decode("", 0, "", 999) |> should.equal(#([], "", 0))
}
