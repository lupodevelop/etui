# Changelog

All notable changes to étui are listed here.

## 2.0.0 - 2026-10-09

Layout and composition primitives, an input parser, and a terminal you can
drive from your own loop.

### Breaking

Most of these fail to compile, so the compiler points at them:

- **`backend.InputEvent` gained `MouseDrag`, `MouseMove` and `Paste`, and
  `backend.RenderOp` gained `EnableBracketedPaste`, `DisableBracketedPaste`,
  `BeginSynchronizedOutput` and `EndSynchronizedOutput`.** A `case` over either
  without a `_ ->` arm no longer compiles. Add the arm.
- **`geometry.split_flex` is removed. Use `split_with`.** The two had the same
  arguments and the same body.
- **The buffer takes a `Style` where it took `fg`, `bg` and `modifier`.**
  `buffer.set_string`, `set_string_linked`, `buffer_new_filled` and
  `continuation_cell` lost two arguments. `buffer.Cell` and `span.Span` hold a
  `style` field instead of the three. Use `style.new(fg, bg, modifier)` at a call
  site that has the three.
- **The poll timeout of `app.run`, `run_buffered`, `run_animated` and
  `run_buffered_cursor` is a `fn(state) -> Int`, not an `Int`.** It is called
  with the current state before each poll, so an app can poll fast while busy
  and slowly while idle. `fn(_) { 16 }` keeps the old behaviour.
- **`ErlangTerminalState`, `NodeState` and `BrowserState` are opaque.** Code that
  only passes the backend around, as `app.run_*` and `terminal.new` do, is
  unaffected.
- **`keys.match` returns `Unknown` rather than `Char` for a multi-grapheme
  string.** Without this, `"shift+left"` would reach a text field as a
  ten-grapheme character. Single graphemes are still `Char`.

### Added

- **Synchronized output.** A frame that emits anything is wrapped in
  `BeginSynchronizedOutput` and `EndSynchronizedOutput` (DEC private mode 2026),
  so the terminal keeps the previous frame until the new one has arrived. A
  terminal without the mode ignores the sequences. `restore_ops` ends the mode
  first, in case an app exits mid-frame.
- **`backend.restore_sequence`, `restore_ops`, `op_to_ansi` and `ops_to_ansi`.**
  One definition of what an app sends the terminal, shared by every target. The
  shell watchdog and the Node exit handler use it. See
  [Terminal state](docs/terminal-state.md).
- **`etui/input`.** Incremental terminal input parsing, testable without a TTY.
  `parse` returns the events it can decode and the bytes that do not yet form a
  complete sequence. `flush` turns a leftover into Escape once a read times out.
- **Modified keys.** Ctrl, alt and shift on arrows, navigation and function keys,
  named in a fixed order (`"ctrl+shift+left"`). These used to reach the app as
  raw escape text.
- **`backend.Paste`.** Pasted text as one event. Opt in with
  `erlang.new_with_options(backend.Options(mouse: False, paste: True))`. It is
  off by default, since an app that ignores `Paste` would see nothing when the
  user pastes.
- **`backend.MouseDrag` and `backend.MouseMove`.** Mouse tracking moved from
  click reporting (1000) to button-event reporting (1002), so drags are reported.
- **`erlang.new_with_options` and `default.new_with_options`.** Take a
  `backend.Options`. `new` and `new_with_mouse` are unchanged.
- **`etui/terminal`.** Drive rendering from your own loop with `new`, `draw`,
  `draw_with`, `poll` and `restore`. The `app.run_*` loops are thin wrappers over
  it.
- **`terminal.Viewport`:** `Fullscreen`, `Inline(height)` and `Fixed(area)`. An
  inline app draws in the bottom rows of the normal screen, leaves the scrollback
  alone, and keeps its last frame on screen when it exits.
- **`geometry.split_with`:** one layout function that takes a `Flex` and a
  spacing. `split`, `split_h`, `split_v` and `split_with_spacing` remain.
- **`geometry.FlexEvenly`:** equal space between children and at both edges.
- **Spacing with every `Flex` mode.** A spacing is a fixed gap on top of the
  leftover, so a toolbar with `FlexBetween` or `FlexAround` can ask for a minimum
  gap between buttons. Before, spacing was ignored in those two modes.
- **`geometry.FillWeighted(weight)`:** proportional flexible space. `Fill` is
  `FillWeighted(1)`, so the two can be mixed.
- **`style.hidden` and `style.rapid_blink`.** Hidden reserves its cells without
  drawing them, which is what a password field needs to keep its layout.
- **Underline colour (SGR 58).** `style.with_underline_color` and
  `span.span_underline_color` set it, and `style.patch` carries it like `fg` and
  `bg`. Terminals without SGR 58 ignore it and draw the underline in the
  foreground colour, as before.
- **`style.new/3`, `style.resolve/1`, `buffer.cell_style` and
  `buffer.cell_underline_color`.** `resolve` settles a style into what a cell
  shows, so two cells that look the same compare equal and a steady frame diffs
  to nothing.
- **`span.Text` and `paragraph.render_text`:** wrapping that keeps styles. A word
  carries the span it came from, so its style moves with it.
- **`keys.parse`, `keys.KeyEvent` and `keys.Modifiers`:** modified keys as data,
  with `pressed`, `pressed_with`, `ctrl`, `alt`, `shift` and `to_string`.
  `to_string` names an event the way it arrived, so `parse` round-trips.
- **`list.settle` and `table.settle`:** the state a widget settles on for a given
  height, so a scroll offset can persist between frames.
- **`buffer.blit/4`:** copy a window of one buffer into another, clipped against
  both. **`buffer.set_style/3`:** repaint a rect without touching cell content.
- **`geometry.Margin`, `inner/2`, `offset/3`, `clamp/2`, `size/1`, `rows/1` and
  `columns/1`:** rect helpers.
- **`text.normalise_newlines/1` and `text.expand_tabs/2`:** for callers that do
  their own wrapping. The tab width is chosen per call.

### Documentation

- **[Migration guide](docs/migrating-to-2.0.md).** The 1.0.1 figures in it were
  measured by running 1.0.1 at its tag. The 2.0.0 figures and snippets are
  checked by `test/migration_examples_test.gleam`.
- **[Terminal state](docs/terminal-state.md).** What is restored on exit, what
  happens when nothing gets to run, and the part of SIGINT that no library can
  handle for you.
- **Widget sections described widgets that had been rewritten.** `canvas` was
  documented with `set_pixel` and `line`, `scene` with an `add` that does not
  exist, `line` with a direction argument, and `hbar` with its old constructor
  name. `dev/check_docs_api.py` checks every name in the docs against `src/`.
- **The spinner styles list** named two styles that do not exist and omitted
  nine that do.
- **`getting-started.md`** asked for `etui = ">= 1.0.0 and < 2.0.0"`, listed an
  `InputEvent` missing three variants, and described Ctrl+C in raw mode wrongly.

### Fixed

- **Editing non-ASCII text on JavaScript cut in the wrong place.**
  `string.drop_start` counts UTF-8 bytes and then slices by UTF-16 units, so box
  drawing, CJK and emoji came back wrong. `input`, `textarea`, `marquee` and
  `line_gauge` now use `text.drop_graphemes`, which counts graphemes on both
  targets.
- **The Node and browser backends could not start.** `node_ffi.mjs` and
  `browser_ffi.mjs` used `new Ok(...)` in `windowSize` without importing `Ok`,
  so initialising either threw a `ReferenceError`.
- **Closed input spun the Erlang backend.** The keyboard reader turned EOF into
  an empty chunk and read again at once, flooding the app with ticks. EOF and a
  failed read now end the reader, and `poll` returns an I/O error. The app loop
  treats that as a quit and restores the terminal.
- **Wide symbols below U+1F300 were one cell short.** U+231A, U+2615, U+26A1,
  U+2705, U+274C, U+2B50 and the other East Asian Wide symbols outside the CJK
  blocks measured one cell, where terminals draw two. Everything after one on a
  row landed a column to the left. They are listed by code point, since the
  block cannot tell them apart from narrow symbols.
- **A grapheme wider than the row hung the styled wrapper.** At width 1 a CJK
  character or emoji fits nowhere, so `span.wrap_line` retried forever. A row
  that is still empty now takes the grapheme, which gets a row of its own.
  `text.wrap` already did this.
- **Wrapping was quadratic.** `span.wrap_line` measured and re-joined the rest of
  a long word on every row, and `text.wrap` rebuilt the line it was assembling
  on every word. A word is now cut in one pass over its graphemes, and a
  zero-width grapheme at the end of a full row stays on that row.
- **`buffer.clear` was quadratic.** Its inner loop appended to lists and copied
  strings. It is linear now.
- **Escape and the first half of an escape sequence were confused.** A read that
  ended mid-sequence became Escape as soon as the next read came back empty. A
  zero-wait poll, or a resize wake on JavaScript, returns empty at once, so the
  first half of an arrow key became Escape. With a long timeout, a real Escape
  waited the whole timeout. The backends now wait 40 ms after the last byte for
  the rest of a sequence, whatever the poll timeout, and a bracketed paste that
  stops mid-way waits one second.
- **The Erlang buffer fill kept its own width table.** `etui_buffer_array_ffi`
  had a copy of `text.codepoint_cell_width` that had drifted: it widened
  U+1F650..U+1F67F, which `text` measures as one cell. It calls
  `text.codepoint_cell_width` now.
- **Cleanup threw on the JavaScript backends.** `exitRaw` in `node_ffi.mjs` and
  `browser_ffi.mjs` still referred to `escapeTimer` and `escapeBuffer`, which no
  longer exist since parsing moved to `etui/input`. Every cleanup ended in a
  `ReferenceError`.
- **The JavaScript target had none of the input work.** Each FFI carried its own
  JavaScript copy of the key normalisation, which stopped matching the Erlang one
  when parsing moved to `etui/input`. The JavaScript suite only tested pure
  functions, so nothing noticed. Both FFIs now move bytes, and `etui/input` parses
  on every target.
- **Layout could return sizes that did not fit the area.** `[Min(60), Min(60)]` in
  100 cells resolved to 120 cells, and the second panel was silently truncated.
  The property test that should have caught it never generated `Min` or `Max`.
- **A scrollbar with nothing to report painted over the panel border.** A
  full-track thumb conveys nothing, and the scrollbar usually sits on a border
  column, so a list that fitted replaced its border with a solid block.
- **Status bar sections overwrote each other.** Left, right and centre were placed
  independently, so a narrow bar drew them on top of each other. They now get
  disjoint spans and truncate.
- **An underline colour made older terminals blink.** SGR 58 was written with
  semicolons, so a terminal that does not know it reads `ESC[58;5;9m` as three
  ordinary parameters. macOS Terminal showed a red underline as blinking
  struck-through text. The sequence is colon-separated now (`ESC[58:5:9m`,
  `ESC[58:2::R:G:B`), so the values belong to 58 and the whole attribute is
  either understood or skipped.
- **Cleanup was a bash script, on systems without bash.** The watchdog that
  restores the terminal when the runtime dies was `/bin/bash` with `$'\x1b'`
  quoting. On Alpine, NixOS and the BSDs the port never opened, so the safety net
  did not exist. It is POSIX `/bin/sh` now, with octal escape bytes, a fallback
  for a `sleep` that rejects fractions, and the flag file in `TMPDIR`.
- **`stty sane` reset `/dev/null`, not the terminal.** `os:cmd/1` redirects stdin
  from `/dev/null`, so the call meant to restore cooked mode did nothing.
- **The JavaScript backends restored two modes out of six.** Cleanup sent only
  `DisableMouse` and `ExitAltScreen`, so an app that enabled bracketed paste or
  hid the cursor left the terminal that way. Both now send the full sequence on
  `exit`, SIGINT, SIGTERM and SIGHUP, with the exit code the shell expects. The
  handlers are registered once, however many times an app starts.
- **Two watchdogs could each assume the other had cleaned up.** They shared one
  flag file per runtime, so an older orphan could consume the flag meant for a
  newer app. Each watchdog has its own file now.
- **The watchdog printed an error into a terminal it could not repair.** With no
  terminal device to name, it was still installed and pointed at `/dev/tty`,
  which a detached process does not have. It is not installed in that case, and
  terminal detection now also checks the parent process.
- **The three backends each had their own escape-sequence table,** and the copies
  had drifted. `EnableMouse` asked for click tracking (1000) on JavaScript but not
  on Erlang, so the same program saw different mouse events on each.
- **Diffing an unchanged frame is faster on JavaScript.** A cell is compared with
  itself far more often than with anything else, and identity settles that with a
  pointer comparison. The structural walk is left for cells that may differ.
- **The space between two wrapped words took the style of the next word.** The
  styled wrapper drops the separating space at a line break and re-emits it
  between words on the same row, using the following word's style. An underline
  paints a space, so the line under a marked word started one cell early. The
  space now carries the style of its own span.
- **Filling a buffer on JavaScript was quadratic.** The cell store copied the whole
  array on every write. Writes are batched now.
- **Keys were dropped when typing fast or pasting.** The backend turned a whole
  read into one `KeyPress`, so everything after the first key was lost, and a
  sequence split across two reads was mangled. Reads are now decoded into a queue
  and delivered one event at a time.
- **A resize ate the keystroke that arrived with it.** The poll returned `Resize`
  instead of the input event. Both are queued now.
- **Dragging the mouse looked like a stream of clicks.** The SGR decoder ignored
  the motion bit. Scrolling with a modifier held (button code 68 and up) was
  reported as a button press.
- **`\r` corrupted every position after it.** `text.wrap` split on `\n` only, so a
  bare `\r` reached the output. It measures zero cells, so the rest of the line
  drew one column to the left. `\r\n` and a lone `\r` are normalised now.
- **Tabs were silently deleted.** A tab measured 0 cells and the fill FFI drops
  control characters, so `"a\tb"` reached the buffer as `"ab"`. `text.wrap` expands
  tabs to 8-column stops now.
- **Non-ASCII text vanished from `buffer_new_filled` on Erlang.** The native
  `fill_all_rows` path consumed non-ASCII bytes without emitting a cell, so a
  filled row lost every CJK and emoji character. The JavaScript fallback was
  correct, which is how the two targets came to disagree.
- **Wide graphemes broke at clip boundaries.** A window that started on the right
  half of a wide grapheme, or ended on its left half, copied an orphan cell. An
  orphan continuation draws nothing and shifts the row left. `buffer.blit` and both
  fill paths now blank the half that cannot be drawn whole.
- **The last terminal column was unusable.** Auto-wrap made writing the bottom-right
  cell scroll the screen, so the backend reserved a column. DECAWM is now disabled
  for the session and restored on exit.
- **Terminal size was queried once per frame.** `io:columns/0` is a synchronous
  round-trip to the group leader, which also serves the keyboard reader, so the
  two contended. Queries are throttled to 100 ms.
- **Ctrl+S froze the terminal on macOS.** OTP raw mode can leave `IXON` set, so
  the terminal took Ctrl+S to pause output and the app never saw the key. The
  Erlang backend clears it on entry and restores the original setting on exit.

### Changed

- **`scroll_view.state_new` is the constructor's name.** Every other stateful
  widget uses `state_new`. `sv_state_new` stays as an alias.
- **`buffer.diff` returns at once for the same `Buffer` term.** An app that keeps
  its last frame and returns it while nothing changes skips the cell walk. Only
  that case is trusted; distinct buffers with equal cells still go through the
  full diff.
- **`Min` and `Max` resolve differently.** They used to take `budget / count`
  each and let `Fill` absorb the rest. They now take a weight-proportional share,
  bounded by their floor and ceiling, settled iteratively. `[Min(10), Max(20),
  Fill]` in 90 cells was `[30, 20, 40]` and is now `[35, 20, 35]`.
- **`Ratio` carries its fractions forward** instead of rounding each one alone,
  so the cells left for other constraints no longer oscillate as the area grows.
  Layout is not monotone under resize for `Min`, `Max` or `Ratio`. The limit is
  measured, tested and documented on `resolve_sizes`.
- **`geometry.inner` follows ratatui's saturation rule.** The origin moves in by
  the margin, and only the size saturates.
- **`Flex` is the type's name.** `FlexJustify` remains as an alias.
- **`style.remove_modifier` now works through `style.patch`.** A style records the
  modifiers it removes (`sub_modifier`), so a theme that sets bold everywhere can
  be overridden by one widget. In 1.0.1, `patch` could not remove a modifier from
  the base style.
- **CI runs the suite on JavaScript as well as Erlang.** Before, only a smoke app
  ran there, which is why the two targets could diverge unnoticed.

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
