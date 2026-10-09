/// How long a half-read escape sequence may wait for its next byte.
///
/// A read that ends in the middle of a sequence leaves the bytes in `pending`.
/// Whether they are the start of something or a lone Escape press cannot be
/// told from the bytes alone, only from how long nothing followed. The old rule
/// was "the read came back empty", which is wrong both ways: a zero-wait poll
/// or a resize wake is empty at once, and turned the first half of a sequence
/// into Escape; a long idle timeout made a real Escape wait the whole timeout.
///
/// So the wait is the poll's timeout capped at a deadline measured from when
/// the bytes arrived, and an empty read means Escape only once that deadline
/// has passed. Pure, so every backend shares it and it is tested without a
/// terminal.
import etui/backend.{type InputEvent}
import etui/input
import gleam/int
import gleam/string

/// How long after the last byte a lone Escape is taken to be a key press.
@internal
pub const escape_deadline_ms = 40

/// A paste that stops mid-way is slower to give up on: the next chunk of a
/// large paste can easily take longer than an Escape would.
const paste_deadline_ms = 1000

fn deadline_ms(pending: String) -> Int {
  case string.starts_with(pending, "\u{1B}[200~") {
    True -> paste_deadline_ms
    False -> escape_deadline_ms
  }
}

/// How long the next read may block: the poll timeout, or less if a pending
/// sequence is about to run out of time.
@internal
pub fn read_wait(
  pending: String,
  since: Int,
  now: Int,
  timeout_ms: Int,
) -> Int {
  case pending {
    "" -> timeout_ms
    _ -> {
      let left = int.max(0, deadline_ms(pending) - { now - since })
      int.min(timeout_ms, left)
    }
  }
}

/// Turn what a read returned into events, the bytes still pending and when
/// they started waiting. An empty `chunk` is a read that gave nothing, whether
/// it timed out or was woken by a resize.
@internal
pub fn decode(
  pending: String,
  since: Int,
  chunk: String,
  now: Int,
) -> #(List(InputEvent), String, Int) {
  case chunk {
    "" ->
      case pending != "" && now - since >= deadline_ms(pending) {
        True -> #(input.flush(pending), "", 0)
        False -> #([], pending, since)
      }
    _ -> {
      let input.Parsed(events, rest) = input.parse(pending <> chunk)
      #(events, rest, now)
    }
  }
}
