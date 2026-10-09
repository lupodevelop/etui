/// Deciding what a half-read escape sequence is.
///
/// A read can end in the middle of a sequence, and the bytes left over are
/// either its start or a lone Escape press. The bytes cannot say which; only
/// how long nothing followed can. So pending bytes carry the time they arrived,
/// a read waits no longer than the deadline for them, and an empty read turns
/// them into Escape only once the deadline has passed. An empty read before
/// that (a zero-wait poll, a resize wake) keeps them.
///
/// Pure, so the three backends share it and it is tested without a terminal.
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
