# Migrating from 1.x to 2.0

Two kinds of change are in here. The first kind the compiler finds for you:
three types changed shape, four gained variants, eight functions changed
signature, three backend states became opaque and one function was removed.
The second kind it cannot — a handful of calls that still compile and now
answer differently.

Every number and every claim below was measured by running both versions
against the same input. How, and how to redo it, is at the end.

## Start here: you may have nothing to do

If your app is built on `app.run_*` and the widgets — `block`, `paragraph`,
`list`, `table`, `input` and the rest — nothing in this document applies to
you, apart from one argument. Not one widget constructor or signature changed.
The poll timeout of the `app.run_*` loops is now a function, see
"The poll timeout is a function" below.

What did change under them is rendering bugs. A scrollbar with nothing to
report no longer paints over the panel border; status bar sections no longer
overwrite each other; and `buffer_new_filled` no longer drops non-ASCII on the
Erlang target — filling eight cells with `"漢字ab"` gave `"ab      "` in 1.0.1
and gives `"漢字ab  "` now. The full list is in the changelog; none of it needs
anything from you.

Both example apps in this repository compile against 2.0 with no edit at all.
To see that for yourself, without touching your checkout:

```sh
git worktree add /tmp/etui-1.0.1 v1.0.1
cp /tmp/etui-1.0.1/examples/counter/src/counter.gleam /tmp/counter-1.0.1.gleam
# then build that file against this version of etui
```

The changes below are in the layer underneath: the buffer, styles, spans and
the terminal.

## What the compiler will stop on

### `style.Style` has two more fields

```gleam
// 1.x
let s = style.Style(fg: style.Indexed(1), bg: style.Default, modifier: style.bold())

// 2.0
let s = style.new(style.Indexed(1), style.Default, style.bold())
```

The record gained `sub_modifier` (modifiers a style takes *away* from one
underneath it) and `underline_color`. `style.new/3` fills both in with the
"changes nothing" values, so it is the direct replacement for the old
three-field constructor. `style.default_style()`, `bold_style()`,
`with_fg`, `with_bg`, `with_modifier`, `patch` and `color_from_hex` are all
unchanged.

### The buffer takes a `Style`, not three loose fields

```gleam
// 1.x
buffer.set_string(buf, pos, "hello", fg, bg, modifier)
buffer.set_string_linked(buf, pos, "docs", fg, bg, modifier, uri)
buffer.buffer_new_filled(area, " ", fg, bg, modifier)
buffer.continuation_cell(fg, bg, modifier)

// 2.0
buffer.set_string(buf, pos, "hello", style.new(fg, bg, modifier))
buffer.set_string_linked(buf, pos, "docs", style.new(fg, bg, modifier), uri)
buffer.buffer_new_filled(area, " ", style.new(fg, bg, modifier))
buffer.continuation_cell(style.new(fg, bg, modifier))
```

If you already had a `Style` in hand you can now pass it straight through
instead of taking it apart.

The three fields could not have grown a fourth without every one of those
signatures growing with it, which is what `underline_color` needed.

### `buffer.Cell` and `span.Span` hold a style

```gleam
// 1.x
buffer.Cell(content: c, fg: fg, bg: bg, modifier: m, link: "")
span.Span(content: "hi", fg: fg, bg: bg, modifier: m, link: "")

// 2.0
buffer.Cell(content: c, style: style.new(fg, bg, m), link: "")
span.Span(content: "hi", style: style.new(fg, bg, m), link: "")
```

Reading a field follows the same move: `cell.fg` is `cell.style.fg`, and
`sp.modifier` is `sp.style.modifier`. The accessor functions did not change —
`buffer.cell_fg`, `cell_bg`, `cell_modifier`, `cell_symbol` and `cell_link`
all still take a `Cell` and answer the same thing — and `cell_style` and
`cell_underline_color` are new.

A cell holds a *resolved* style: whatever the style took away has already been
taken away, and `sub_modifier` is spent on the way in. Two cells that look
identical therefore compare equal, which is what keeps an unchanged frame from
repainting.

### `geometry.split_flex` is gone

```gleam
// 1.x
geometry.split_flex(Horizontal, area, constraints, FlexBetween, 2)

// 2.0
geometry.split_with(Horizontal, area, constraints, FlexBetween, 2)
```

Same arity, same argument order, same parameters. By the end of the layout
rework the two had the same body as well, and two names for one function is
not an API.

The rename is mechanical, but the *result* is not always identical: where 1.x
mishandled a non-zero spacing, 2.0 does not. See "Spacing composes with flex"
below.

### The poll timeout is a function

```gleam
// 1.x
app.run_buffered(b, model, render, update, quit, 16)

// 2.0
app.run_buffered(b, model, render, update, quit, fn(_) { 16 })
```

`app.run`, `run_buffered`, `run_animated` and `run_buffered_cursor` take the
timeout as `fn(state) -> Int`, called with the current state right before each
poll. A constant is `fn(_) { n }`. An app that wants a short timeout while
something is happening and a long one when it is idle can now say so:

```gleam
fn(m) {
  case m.streaming {
    True -> 33
    False -> 250
  }
}
```

The long timeout is also the longest an event from outside the terminal waits
before the loop notices it.

### The backend states are opaque

`erlang.ErlangTerminalState`, `node.NodeState` and `browser.BrowserState` can
be named in a type but no longer built or taken apart. Passing a backend to
`app.run_*` or `terminal.new` needs no change. Code that read `cols`, `rows`
or `pending` from one should call `terminal.area` or the backend's `next_size`
instead.

### New variants in `backend.InputEvent` and `backend.RenderOp`

`InputEvent` gained `MouseDrag`, `MouseMove` and `Paste`. `RenderOp` gained
`EnableBracketedPaste` and `DisableBracketedPaste`. A `case` over either that
was exhaustive without a `_ ->` arm no longer compiles; adding the arm, or
handling the new events, is the whole fix.

`geometry.Flex` (which `FlexJustify` is now an alias of) gained `FlexEvenly`,
and `geometry.Constraint` gained `FillWeighted`, with the same consequence for
an exhaustive `case`.

## What still compiles and now behaves differently

### Layout: `Min` and `Max` that do not add up

The flexible pass is iterative now. It only changes the result when the
constraints were over- or under-subscribed; every other combination resolves
exactly as it did. Measured in a 100-cell budget:

| Constraints | 1.0.1 | 2.0.0 |
|---|---|---|
| `[Min(60), Min(60)]` | `[60, 60]` — 120 cells of sizes for 100 cells of space | `[50, 50]` |
| `[Min(80), Min(80)]` | `[80, 80]` — 160 for 100 | `[50, 50]` |
| `[Min(50), Max(20)]` | `[50, 20]` — 30 cells left unused | `[80, 20]` |
| `[Min(30), Max(40), Fill]` | `[33, 33, 34]` | `[34, 33, 33]` |
| `[Min(60), Fill]` | `[60, 40]` | `[60, 40]` |
| `[Min(20), Fill]` | `[50, 50]` | `[50, 50]` |
| `[Min(60), Fill, Fill]` | `[60, 20, 20]` | `[60, 20, 20]` |
| `[Max(20), Min(50), Fill]` | `[20, 50, 30]` | `[20, 50, 30]` |
| `[Max(10), Fill]` | `[10, 90]` | `[10, 90]` |
| `[Length(10), Fill, Fill]` | `[10, 45, 45]` | `[10, 45, 45]` |
| `[Percentage(30), Fill]` | `[30, 70]` | `[30, 70]` |
| `[Ratio(1, 3), Fill]` | `[33, 67]` | `[33, 67]` |

The first row is the one that used to bite: two identical constraints came out
different sizes, because `build_rects` truncated the second to whatever was
left.

One thing that did *not* change and still surprises people: `[Max(30),
Max(30)]` in 100 cells is `[30, 30]` in both versions, and the other 40 cells
belong to nobody. `Max` is a ceiling, not a claim. Add a `Fill` if something
should have the rest.

### Spacing composes with flex

Three 6-cell children in 40 cells, `FlexBetween`, spacing 2:

| | first | second | third | right edge |
|---|---|---|---|---|
| 1.0.1 `split_flex` | x=0 | x=15 | x=30 | ends at 36, four cells short |
| 2.0.0 `split_with` | x=0 | x=17 | x=34 | ends at 40 |

In 1.x the spacing was taken out of the budget and then the leftover was
spread again, so a "space between" layout stopped short of the edge it is
supposed to reach. In 2.0 the spacing is a floor that the larger gaps absorb.
`FlexStart` with spacing is unchanged: `x=0, 8, 16` in both.

### `keys.match` and multi-grapheme keys

```gleam
keys.match("shift+left")
// 1.0.1: Char("shift+left")
// 2.0.0: Unknown("shift+left")
```

Modified keys reach an app now, and in 1.x a text field would have inserted
that ten-grapheme "character" into its content. Single graphemes are still
`Char`, so ordinary typing is unaffected, and `keys.match("ctrl+c")` is still
`Ctrl("c")`.

Reach for `keys.parse` when you want the modifier as data:

```gleam
case keys.parse(raw) {
  keys.KeyEvent(keys.Left, keys.Modifiers(shift: True, ..)) -> select_left(model)
  keys.KeyEvent(keys.Left, _) -> move_left(model)
  _ -> model
}
```

### `text.wrap` normalises what it is given

```gleam
text.wrap("a\tb", 20)
// 1.0.1: ["a\tb"]      — the tab measured 0 cells and the buffer then dropped it
// 2.0.0: ["a       b"] — expanded to the next 8-column tab stop

text.wrap("a\r\nb", 20)
// 1.0.1: ["a\r", "b"]  — the CR measured 0 cells and shifted the row left
// 2.0.0: ["a", "b"]
```

### Some symbols are two cells

⌚ ☕ ⚡ ✅ ❌ ⭐ and the other East Asian Wide symbols below U+1F300 measured one
cell in 1.x and measure two now, which is how terminals draw them.
`text.cell_width("⚡")` is `2`. The rest of those blocks (✦ ★ ◆ ☆) stays at one.
A table laid out around one of these characters moves its border one column
right, to where it should have been.

### Mouse tracking on the JavaScript targets

`EnableMouse` used to emit `?1000h ?1002h ?1006h` on Node and in the browser
and `?1002h ?1006h` on Erlang: three copies of one table had drifted. There is
one table now and every target sends `?1002h ?1006h`. Button-event tracking
(1002) reports what click tracking (1000) does and motion with a button held
besides, which is what makes `MouseDrag` possible. Disabling is unchanged and
still clears every mode including 1000.

## Worth adopting, none of it required

- **`etui/terminal`** — `new`, `draw`, `draw_with`, `poll`, `restore`: the loop
  comes back to you, and `app.run_*` is a thin wrapper over it.
- **`terminal.Viewport`** — `Fullscreen`, `Inline(height:)`, `Fixed(area:)`,
  chosen with `terminal.new_with_viewport`. An inline app draws in the bottom
  rows of the normal screen and leaves its last frame behind when it exits.
- **`etui/input`** — the parser as a pure function: `parse` takes a chunk and
  returns the events it could decode plus the bytes that do not yet form a
  sequence, and `flush` resolves a leftover once a read times out. No TTY
  needed to test it.
- **`geometry.FillWeighted(n)`** — `Fill` is `FillWeighted(1)`, so the two mix.
- **`span.Text` and `paragraph.render_text`** — wrapping that carries each
  span's style with its words.
- **`style.with_underline_color`** — an underline in a colour of its own
  (SGR 58), for a spell-check squiggle under text that keeps its colour.
- **`backend.restore_sequence`** — everything an app must undo, in one string,
  if you are driving a terminal yourself.

## One thing to know about signals

In raw mode Ctrl+C is not a signal: it arrives as the key `"ctrl+c"` for your
app to handle. A signal sent from elsewhere is another matter — the BEAM keeps
SIGINT for its own break handler and refuses to hand it over (measured on
OTP 29), so `kill -INT` leaves an app sitting at the break prompt with the
terminal still borrowed. Start the VM with `+B` if that matters:

```sh
ERL_FLAGS="+B" gleam run
```

[Terminal state](terminal-state.md) has the rest, including what is restored
and what happens when the runtime dies without unwinding.

## How the numbers here were produced

Every "1.0.1" figure came from running 1.0.1, not from reading its source:

```sh
git worktree add /tmp/etui101 v1.0.1
# put the same probe module in /tmp/etui101/test/ and in test/
cd /tmp/etui101 && gleam test     # the 1.0.1 column
cd -            && gleam test     # the 2.0.0 column
```

The 2.0 code in this guide is compiled on every test run, and every 2.0 figure
in its tables is asserted, by `test/migration_examples_test.gleam`. Two
checkers keep the guide and the API honest about each other:

```sh
python3 dev/check_guide_snippets.py   # the guide says only what the tests assert
python3 dev/check_docs_api.py         # every name in every doc exists in src/
```

The second one is how the widget documentation was found to describe four
widgets that had been rewritten underneath it.
