/// Handing the terminal back.
///
/// Cleanup runs when things have already gone wrong, so none of it can be
/// checked by running an app and looking. What can be checked is that the
/// bytes are right, that there is one definition of them, and that the shell
/// fallback which fires when the runtime dies without unwinding is a script
/// every POSIX shell can run.
import etui/backend
import gleam/string
import gleeunit/should

// ─────────────────────────────────────────────────────────────────
// The sequence

pub fn restore_turns_off_every_mode_an_app_turns_on_test() {
  let seq = backend.restore_sequence()

  // Mouse reporting, in all the encodings a terminal might have accepted.
  string.contains(seq, "\u{001B}[?1000l") |> should.equal(True)
  string.contains(seq, "\u{001B}[?1002l") |> should.equal(True)
  string.contains(seq, "\u{001B}[?1006l") |> should.equal(True)
  // Bracketed paste, which is opt-in and was never in the old cleanup.
  string.contains(seq, "\u{001B}[?2004l") |> should.equal(True)
  // A frame held by synchronized output.
  string.contains(seq, "\u{001B}[?2026l") |> should.equal(True)
  // The alternate screen.
  string.contains(seq, "\u{001B}[?1049l") |> should.equal(True)
  // And the three things an app changes without a RenderOp for them.
  string.contains(seq, "\u{001B}[?7h") |> should.equal(True)
  string.contains(seq, "\u{001B}[0m") |> should.equal(True)
  string.contains(seq, "\u{001B}[?25h") |> should.equal(True)
}

/// The cursor comes back last. Anything after it could hide it again, and an
/// invisible cursor in the shell is the failure users actually report.
pub fn the_cursor_is_the_last_thing_restored_test() {
  backend.restore_sequence()
  |> string.ends_with("\u{001B}[?25h")
  |> should.equal(True)
}

/// Leaving the alternate screen after the modes are cleared, not before: the
/// modes belong to the screen the app was drawing on.
pub fn modes_are_cleared_before_leaving_the_alt_screen_test() {
  let seq = backend.restore_sequence()
  case string.split_once(seq, "\u{001B}[?1049l") {
    Error(_) -> should.fail()
    Ok(#(before, _)) -> {
      string.contains(before, "\u{001B}[?1000l") |> should.equal(True)
      string.contains(before, "\u{001B}[?2004l") |> should.equal(True)
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// The op table
//
// One table for every backend now. Each used to carry its own copy, and the
// copies had drifted: this is the pair that differed.

pub fn mouse_tracking_is_the_same_on_every_target_test() {
  backend.op_to_ansi(backend.EnableMouse)
  |> should.equal("\u{001B}[?1002h\u{001B}[?1006h")
}

pub fn ops_to_ansi_concatenates_in_order_test() {
  backend.ops_to_ansi([backend.EnterAltScreen, backend.Write("x")])
  |> should.equal("\u{001B}[?1049hx")
}
