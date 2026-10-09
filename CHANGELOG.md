# Changelog

All notable changes to étui are listed here.

## 2.0.0 - unreleased

Ratatui-level flexibility. Layout and composition primitives, a real input
parser, and a Terminal you can drive from your own loop.

### Breaking

Small, but they will not compile silently:

- **`backend.InputEvent` gained `MouseDrag`, `MouseMove` and `Paste`**, and
  **`backend.RenderOp` gained `EnableBracketedPaste`,
  `DisableBracketedPaste`, `BeginSynchronizedOutput` and
  `EndSynchronizedOutput`**. A `case` over either that was exhaustive without a
  `_ ->` arm now fails to compile. Adding the arm is the whole fix.
- **`geometry.split_flex` is gone; use `split_with`.** After the layout rework
  the two had the same arity, the same argument order and the same body, and
  two names for one function is not an API.
- **The buffer takes a `Style` where it used to take `fg`, `bg` and
  `modifier`.** `buffer.set_string`, `set_string_linked`, `buffer_new_filled`
  and `continuation_cell` all lost two arguments, and `buffer.Cell` and
  `span.Span` hold a `style` field in place of the three. `style.new(fg, bg,
  modifier)` is the one-line fix at a call site that has the three on hand.
  The three fields could not grow a fourth without every one of those
  signatures growing with it, which is what `underline_color` needed.
- **The poll timeout of `app.run`, `run_buffered`, `run_animated` and
  `run_buffered_cursor` is a `fn(state) -> Int`,** not an `Int`. It is called
  with the current state before each poll, so an app can poll fast while it is
  busy and slowly while it is idle. `fn(_) { 16 }` is the old behaviour.
- **`ErlangTerminalState`, `NodeState` and `BrowserState` are opaque.** Their
  fields were never meant to be read or built from outside the backends, and
  each new field would have been a source break. Code that only passes the
  backend around, as `app.run_*` and `terminal.new` do, is unaffected.
- **`keys.match` answers `Unknown` rather than `Char` for a multi-grapheme
  string.** With modified keys now reaching the app, `"shift+left"` would have
  arrived at a text field as a ten-grapheme "character" to insert. Single
  graphemes are still `Char`, so ordinary typing is unaffected.

### Added

- **Synchronized output.** A frame that emits anything is wrapped in
  `BeginSynchronizedOutput` and `EndSynchronizedOutput` (DEC private mode 2026),
  so the terminal keeps the old frame on screen until the new one has arrived
  instead of painting it halfway. A terminal that does not know the mode
  ignores the sequences. A frame with nothing to emit still emits nothing, and
  `restore_ops` ends the mode first, in case an app dies mid-frame.
- **`backend.restore_sequence`, `restore_ops`, `op_to_ansi` and `ops_to_ansi`:**
  one definition of what an app sends the terminal, shared by every target and
  handed to the two places that cannot call Gleam — the shell watchdog and the
  Node exit handler. See the new [Terminal state](docs/terminal-state.md)
  guide.
- **`etui/input`:** incremental terminal input parsing, pure and testable
  without a TTY. `parse` returns every event it can decode plus the bytes that
  do not yet form a complete sequence; `flush` resolves a leftover into Escape
  once a read times out.
- **Modified keys:** ctrl, alt and shift on arrows, navigation and function
  keys, named in a fixed order (`"ctrl+shift+left"`). These previously reached
  the app as raw escape text.
- **`backend.Paste`:** pasted text as one event. Opt in with
  `erlang.new_with_options(backend.Options(mouse: False, paste: True))`. It is
  off by default because an app that ignores `Paste` would see nothing at all
  when the user pastes.
- **`backend.MouseDrag` and `backend.MouseMove`,** with mouse tracking raised
  from click reporting (1000) to button-event reporting (1002) so drags are
  actually reported.
- **`erlang.new_with_options` and `backend.Options`.** `new` and
  `new_with_mouse` are unchanged. `default.new_with_options` is the same call
  on both targets.
- **`etui/terminal`:** drive rendering from your own loop. `new`, `draw`,
  `draw_with`, `poll`, `restore`. The `app.run_*` loops are thin wrappers over
  it now, and `app.gleam` went from 969 lines to 522 as a result.
- **`terminal.Viewport`:** `Fullscreen`, `Inline(rows)` and `Fixed(rect)`. An
  inline app draws in the bottom rows of the normal screen, leaves the
  scrollback alone, and leaves its last frame on screen when it exits, which is
  the shape a build tool or an installer wants.
- **`geometry.split_with`:** one layout function taking a `Flex` and a spacing.
  `split`, `split_h`, `split_v`, `split_with_spacing` and `split_flex` are all
  this with arguments filled in.
- **`geometry.FlexEvenly`,** and spacing that composes with the modes that
  place their own gaps. `split_flex` documented spacing as ignored for
  `FlexBetween` and `FlexAround`, so a toolbar could ask for a minimum gap
  between buttons and silently not get one.
- **`geometry.FillWeighted(weight)`:** proportional flexible space. `Fill` is
  `FillWeighted(1)`, so the two mix.
- **`style.sub_modifier`:** a style can now take a modifier away, not only add
  one. A theme that sets bold everywhere and one widget that must not be bold
  was previously impossible to express.
- **`style.underline_color` (SGR 58):** an underline in a colour of its own,
  independent of the text it sits under — a red squiggle under black text,
  which is the thing underlines are most used for and the one thing they could
  not say. `style.with_underline_color` and `span.span_underline_color` set it,
  `style.patch` layers it like `fg` and `bg`. Terminals without SGR 58 ignore
  the sequence and draw the underline in the foreground colour, exactly as
  before.
- **`style.new/3` and `style.resolve/1`,** and the buffer accessors
  `cell_style` and `cell_underline_color`. `resolve` settles a style into what
  a cell shows: a cell holds no unspent `sub_modifier`, so two cells that look
  identical compare equal and a steady frame diffs to nothing.
- **`style.hidden` and `style.rapid_blink`.** Hidden reserves its cells without
  drawing them, which is what a password field wants when it has to keep its
  layout.
- **`span.Text`:** wrapping that keeps the styles. Words carry the span they
  came from, so a style travels with its word rather than with the column the
  word started in. `paragraph.render_text` draws it.
- **`keys.parse`, `keys.KeyEvent`, `keys.Modifiers`:** modified keys as data.
  With `is`, `is_combo`, `ctrl`/`alt`/`shift`, and `to_string`, which names an
  event the way it arrived so `parse` round-trips.
- **`list.settle` and `table.settle`:** the state a widget will settle on for a
  given height, so a scroll offset can persist between frames.
- **`buffer.blit/4`:** copy a window of one buffer into another, clipped
  against both. Composite an off-screen canvas or a cached panel into the frame
  without walking cells from the caller.
- **`buffer.set_style/3`:** repaint a rect without touching cell content.
- **`geometry.Margin`, `inner/2`, `offset/3`, `clamp/2`, `size/1`, `rows/1`,
  `columns/1`:** the rect helpers ratatui exposes on `Rect`. `inner/2` follows
  ratatui's saturation rule.
- **`text.normalise_newlines/1` and `text.expand_tabs/2`:** exposed so callers
  that do their own wrapping can apply the same normalisation, and so tab width
  can be chosen per call site.

### Documentation

- **A migration guide** — [docs/migrating-to-2.0.md](docs/migrating-to-2.0.md).
  Every "1.0.1" figure in it was produced by running 1.0.1 in a worktree at the
  tag, not by reading its source; every "2.0.0" figure is asserted by
  `test/migration_examples_test.gleam`, which is also where its snippets are
  compiled.
- **[docs/terminal-state.md](docs/terminal-state.md)** — what is restored on the
  way out, what happens when nothing gets to run, and the one thing about
  SIGINT that no library can fix for you.
- **Four widget sections described widgets that had been rewritten underneath
  them.** `canvas` was documented with `set_pixel` and `line`, which it has
  never had in this shape; `scene` with an `add` that does not exist; `line`
  with a direction argument that is two separate functions; `hbar` with a
  constructor renamed to `HBarItem`. `dev/check_docs_api.py` reads the public
  API out of `src/` and checks every name in every doc against it, which is how
  these were found.
- **The spinner styles list named two that do not exist** and omitted nine that
  do.
- `getting-started.md` still asked for `etui = ">= 1.0.0 and < 2.0.0"`, listed
  an `InputEvent` missing three variants, and recommended a way of handling
  Ctrl+C that misdescribes what Ctrl+C does in raw mode.

### Fixed

- **Editing text with non-ASCII characters on JavaScript cut the wrong place.**
  `string.drop_start` counts UTF-8 bytes of the prefix and then slices by UTF-16
  units, so box drawing, CJK and emoji came back wrong. `input`, `textarea`,
  `marquee` and `line_gauge` now use the new `text.drop_graphemes`, which counts
  graphemes on both targets.
- **The Node and browser backends could not start.** `node_ffi.mjs` and
  `browser_ffi.mjs` built `new Ok(...)` in `windowSize` without importing `Ok`,
  so initialising either backend threw a `ReferenceError`. No test started a
  backend, only pure functions ran.
- **Closed input spun the Erlang backend.** The keyboard reader turned EOF into
  an empty chunk and asked again at once, which flooded the app with ticks, and
  the cleanup drain never finished with stdin closed. EOF and a failed read now
  end the reader, and `poll` returns an I/O error. The app loop treats that as
  a quit and restores the terminal.
- **Wide symbols below U+1F300 were one cell short.** ⌚ ☕ ⚡ ✅ ❌ ⭐ and the
  rest of the East Asian Wide symbols outside the CJK blocks measured one cell
  where terminals draw two, so everything after one on a row landed a column
  left of the cursor. They are listed by code point, since the block cannot
  tell them from ✦ ★ ◆ ☆.
- **The styled wrapper never returned for a grapheme wider than the row.** At
  a width of 1 a CJK character or an emoji fits nowhere, so `span.wrap_line`
  put the same word back and tried again. A row that is still empty now always
  takes the grapheme in front of it, so such a grapheme gets a row of its own
  and is the only thing that can make a row wider than asked. `text.wrap`
  already did this.
- **Wrapping a long word was quadratic.** Each row measured and re-joined all of
  the word that was left. A word is now cut into rows in one pass over its
  graphemes. A zero-width grapheme at the end of a full row stays on that row.
- **Ctrl+S froze the terminal on macOS.** OTP raw mode can leave `IXON` set,
  so the terminal took Ctrl+S to pause output and the app never saw the key.
  The Erlang backend clears it on entry and restores what the terminal had on
  exit.
- **Escape and the first half of an escape sequence were confused.** A read
  that ended mid-sequence was turned into Escape as soon as the next read came
  back empty. A zero-wait poll, or on JavaScript a resize wake, comes back empty
  at once, so the first half of an arrow key became Escape. With a long poll
  timeout the opposite happened: a real Escape waited the whole timeout. The
  backends now wait up to 40 ms after the last byte for the rest of a sequence,
  whatever the timeout, and only then call it Escape. A bracketed paste that
  stops mid-way waits one second.
- **The Erlang buffer fill kept its own width table.** `etui_buffer_array_ffi`
  copied `text.codepoint_cell_width` and the copy had drifted: it widened
  U+1F650..U+1F67F, which `text` measures at one cell. It now calls
  `text.codepoint_cell_width`, so there is one table.
- **Cleanup threw on the JavaScript backends.** `exitRaw` in `node_ffi.mjs` and
  `browser_ffi.mjs` still referred to `escapeTimer` and `escapeBuffer`, which
  stopped existing when parsing moved to `etui/input`. Modules are strict, so
  every cleanup ended in a `ReferenceError`.
- **The JavaScript target had none of the input work.** `node_ffi.mjs` and
  `browser_ffi.mjs` each carried a JavaScript reimplementation of the key
  normalisation, announced as mirroring the Erlang one. It stopped mirroring
  anything the moment the Erlang side moved to `etui/input`, and the JavaScript
  suite only exercised pure functions, so nothing noticed. Both FFIs now move
  bytes and `etui/input` does the parsing on every target.
- **Layout could return sizes that did not fit the area.**
  `[Min(60), Min(60)]` in 100 cells resolved to 120 cells of sizes and the
  second panel was silently truncated, so two identical constraints came out
  different sizes. The property test that should have caught this had never
  been run against `Min` or `Max`: its generator only emitted `Length`,
  `Percentage` and `Fill`.
- **A scrollbar with nothing to report painted over the panel border.** A
  full-track thumb conveys nothing and the scrollbar usually sits on a border
  column, so a list that fitted its panel replaced the border with a solid
  block.
- **Status bar sections overwrote each other.** Left, right and centre were
  placed independently, so a narrow bar rendered them on top of one another.
  They now get disjoint spans and truncate instead.
- **An underline colour made older terminals blink.** SGR 58 was written with
  semicolons, and to a terminal that does not implement it `ESC[58;5;9m` is
  three ordinary parameters: unknown, then 5, then 9. macOS Terminal read a red
  underline as blinking struck-through text and a green one as blinking dim
  text. The sequence is colon-separated now — `ESC[58:5:9m`,
  `ESC[58:2::R:G:B` — so the values belong to the 58 and the whole attribute is
  either understood or skipped.
- **Cleanup was a bash script, on systems that need not have bash.** The
  watchdog that hands the terminal back when the runtime dies without
  unwinding was `/bin/bash` with `$'\x1b'` ANSI-C quoting. Where /bin holds no
  bash — Alpine, NixOS, a BSD — the port never opened and the safety net
  silently did not exist. It is POSIX `/bin/sh` now, with the escape bytes
  octal-escaped so no shell has to be trusted with a quoting rule, a fallback
  for a `sleep` that will not take a fraction, and the flag file in `TMPDIR`
  rather than an assumed `/tmp`.
- **`stty sane` reset `/dev/null`, not the terminal.** `os:cmd/1` runs with
  stdin redirected from /dev/null and stty acts on its standard input, so the
  call that was supposed to restore cooked mode had been doing nothing at all.
- **The JavaScript backends restored two modes out of six.** Node and browser
  cleanup sent `DisableMouse` and `ExitAltScreen` only: an app that turned on
  bracketed paste or hid the cursor left the terminal that way. Both send the
  full sequence now, on `exit`, SIGINT, SIGTERM and SIGHUP, with the exit code
  the shell expects, registered once however many times an app starts.
- **Two watchdogs could agree that neither had to do anything.** They shared
  one flag file per runtime, so an app that entered raw mode twice could have
  the older orphan consume the flag meant for the newer one, leaving both
  convinced the exit had been clean. One file per watchdog now.
- **The watchdog printed an error into the terminal it could not repair.**
  With no way to name a terminal device it was installed anyway, pointed at
  `/dev/tty`, which means nothing to a process detached from the session:
  `/bin/sh: /dev/tty: Device not configured`. It is not installed in that case,
  and terminal detection now also asks about the parent process, which is
  where a runtime started without its own controlling terminal usually finds
  one.
- **The three backends each kept their own copy of the escape-sequence
  table,** and the copies had drifted: `EnableMouse` asked for click tracking
  (1000) on the JavaScript targets and not on Erlang, so the same program
  reported subtly different mouse events depending on where it ran.
- **Diffing a steady frame got cheaper on JavaScript, not more expensive.**
  A cell is compared against itself far more often than against anything else,
  and identity settles that in a pointer compare; the structural walk is left
  for cells that might actually differ. An unchanged 200x50 frame diffs in
  54 us where it took 124 us in 1.0, and a full repaint in 4.0 ms where it
  took 6.9 ms.
- **The space between two wrapped words took the style of the word after it.**
  The styled wrapper drops the separating space at a line break and re-emits it
  between words that share a row; it re-emitted it with the following word's
  style. Nothing noticed while styles were colours on glyphs, because a space
  has no glyph to colour, but an underline does paint a space, so the line
  under a marked word started one cell early. The space now carries the style
  of the span it came from, which also keeps a highlighted phrase whole rather
  than punching a hole where each space was.
- **Wrapping was quadratic in the length of a line.** `text.wrap` measured and
  rebuilt the line it was assembling on every word, which made it five times
  slower than the styled wrapper that does strictly more work.
- **Filling a buffer on JavaScript was quadratic in its size.** The cell store
  copied the whole array on every cell written, so a 200x50 fill cost 35 ms,
  more than a 60 fps frame, and one showcase frame cost 16.8 ms. Writes are
  batched now: 2.4 ms and 3.9 ms.
- **Keys were dropped when typing fast or pasting:** the backend turned an
  entire read into one `KeyPress`, so everything after the first key in a
  buffered read was lost, and a sequence split across two reads was mangled.
  Reads are now decoded into a queue and delivered one event at a time.
- **A resize ate the keystroke that arrived with it:** the poll returned
  `Resize` *instead of* the input event. Both are queued now.
- **Dragging the mouse looked like a stream of clicks:** the SGR decoder
  ignored the motion bit. Scrolling with a modifier held (button code 68 and
  up) was also reported as a button press.
- **`\r` corrupted every position after it:** `text.wrap` split on `\n` only,
  leaving a bare `\r` in the output. It measures zero cells, so the rest of the
  line drew one column to the left. `\r\n` and lone `\r` are now normalised.
- **Tabs were silently deleted:** a tab measured 0 cells and the fill FFI drops
  control characters, so `"a\tb"` reached the buffer as `"ab"`. `text.wrap` now
  expands tabs to 8-column tab stops.
- **Non-ASCII text vanished from `buffer_new_filled` on Erlang:** the native
  `fill_all_rows` path consumed non-ASCII bytes without emitting a cell, so a
  filled row lost every CJK and emoji character. The JavaScript fallback was
  correct, which is how the two targets came to disagree.
- **Wide graphemes broke at clip boundaries:** a window that started on the
  right half of a wide grapheme, or ended on its left half, copied an orphan.
  An orphan continuation renders as nothing and shifts the row left; an orphan
  wide cell draws over its neighbour. `buffer.blit` and both fill paths now
  blank the half that cannot be drawn whole.
- **The last terminal column was unusable:** auto-wrap made writing the
  bottom-right cell scroll the screen, so the backend reserved a column.
  DECAWM is now disabled for the session and restored on exit.
- **Terminal size was queried once per frame:** `io:columns/0` is a synchronous
  round-trip to the group leader that also serves the keyboard reader, putting
  the two in contention. Queries are throttled to 100 ms.

### Changed

- **`scroll_view.state_new` is the constructor's name.** Every other stateful
  widget uses `state_new`. `sv_state_new` stays as an alias.
- **`buffer.diff` returns at once for the same `Buffer` term.** An app that
  keeps its last frame and returns it while nothing changes skips the cell
  walk. Only a hit is trusted: distinct buffers with equal cells still go
  through the full diff.
- **`Min` and `Max` resolve differently.** They were sized by one pass that
  gave each `budget / count` and let `Fill` absorb the rest; they now take a
  weight-proportional share bounded by their floor and ceiling, settled
  iteratively. `[Min(10), Max(20), Fill]` in 90 cells was `[30, 20, 40]` and is
  now `[35, 20, 35]`: the ten cells `Max` gives up are shared, because `Min` is
  documented as a flexible participant and has as much claim on them as `Fill`.
- **`Ratio` accumulates its fractions** rather than rounding each one alone,
  which stops the cells left for anything else oscillating as the area grows.
  Layout is not monotone under resize for `Min`, `Max` and `Ratio`; the limit
  is measured, pinned by tests and documented on `resolve_sizes`.
- **`geometry.inner` follows ratatui's saturation rule:** the origin moves in
  by the margin unconditionally and only the size saturates.
- **`Flex` is the type's name,** with `FlexJustify` kept as an alias.
- **`buffer.clear` is O(n):** it had quadratic accumulation (list appends,
  string copies) in its inner loop. `text.wrap` is under Fixed.
- **CI runs the suite on JavaScript as well as Erlang.** Only a smoke app ran
  there before, which is why the two targets could diverge unnoticed.

## 1.0.1 - 2026-06-06

### Fixed

- **Keyboard I/O dropped keys (#2, #4):** replaced spawn/kill polling loop in
  `etui_terminal_ffi.erl` with persistent `etui_kbd_reader` actor. Reader
  blocks on `io:get_chars` and forwards `{etui_input, Bin}` to owner.
  Eliminates dropped keys and TTY lock contention in 60FPS loops.
  Thanks [@salespaulo](https://github.com/salespaulo).
- **Input widget horizontal scroll (#3, #5):** removed hardcoded `- 2`
  column margin in `widgets/input` truncation and cursor tracking. Uses
  full `area.size.width` via `int.max(1, area.size.width)`. Cursor no
  longer jumps prematurely; widget fills assigned cells.
  Thanks [@salespaulo](https://github.com/salespaulo).

## 1.0.0 - 2026-05-27

First public release.

### Added

- Buffer-diff rendering with cell-accurate Unicode (UAX #29 grapheme clusters).
- Layout primitives: `Length`, `Min`, `Max`, `Percentage`, `Ratio`, `Fill`,
  plus `split_with_spacing`, `split_flex`, `split_responsive`.
- 32 widgets: block, paragraph, list, table, tabs, gauge, line_gauge, hbar,
  chart, sparkline, canvas, input, textarea, tree, scrollbar, popup, statusbar,
  spinner, marquee, dialog, form, notification, scene, progress, gradient_bar,
  line, clear, scroll_view, paginator, help, fieldset, multi_select.
- Bubbletea-inspired additions (port of ratatui-cheese ideas):
  - Spinner gains 10 presets (MiniDot, Jump, Pulse, Points, Globe, Moon,
    Monkey, Meter, Hamburger, Ellipsis) on top of Dots, Line, Circle, Bounce.
  - Tree supports a right-aligned count per node via `leaf_with_count`,
    `node_with_count` and `with_count`.
  - Input gains `with_prompt`, `with_password`, `with_mask` for prompt
    prefixes and masked password fields.
  - Paginator: dot or arabic page indicator, with `slice/2` helper.
  - Help: short single-line and full multi-column key bindings view.
  - Fieldset: horizontal rule with inline title (left/center/right).
  - MultiSelect: toggle list with optional `max` cap and cursor scrolling.
- 10 built-in themes: dracula, nord, catppuccin_mocha, catppuccin_latte,
  monokai, solarized_dark, gruvbox_dark, tokyo_night, dark, light.
- App loops with crash-restore on Erlang `try/after`: `run`, `run_buffered`,
  `run_animated`, `run_buffered_cursor`.
- Backends for Erlang/BEAM, Node.js and the browser. `etui/backend/default`
  picks one at compile time.
- Typed keyboard input via `keys.match`, command tables via `keymap`,
  multi-slot focus via `focus`, integer-math easing via `anim`.
- Composition helpers in `etui/widget`: `layer`, `at`, `compose`, `stack`,
  `StatefulWidget`, `AnimatedWidget`.
- Test mock backend for app-loop coverage (`test/app_loop_test`).
