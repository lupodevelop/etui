# Contributing

Thanks for helping improve étui. This is a **library** (not an application): keep changes small, tested, and API-stable after 1.0.

## Setup

- Gleam **1.16+** (see CI).
- Erlang/OTP **26+** for terminal development.
- Node **22+** only if you work on the JavaScript target or run `etui_js_smoke`.

```sh
gleam deps download
gleam test
gleam format src test dev
```

## Layout

| Path | Role |
| --- | --- |
| `src/etui/` | Public library code (published to Hex). |
| `src/etui/widgets/` | Widget renderers. |
| `test/` | gleeunit tests (headless). |
| `dev/` | Demos, benches, JS smoke — **not** published. |
| `docs/` | User-facing guides (keep in sync with API). |

## Conventions

1. **Widget render signature:** `fn(Buffer, Rect, Widget) -> Buffer` (or `render_stateful` with external state).
2. **Pipe style:** `buffer.buffer_new(area) |> widget.render(area, w)` — buffer first via `|>`.
3. **Pure core:** `geometry`, `text`, `buffer`, widgets must not import `backend`.
4. **Docs:** update `docs/` when changing public API, and run the two checkers
   below. Snippets that must compile live in `doc_snippets_compile_test`
   (`test/app_loop_test.gleam`) and `test/migration_examples_test.gleam`.
5. **Format:** `gleam format` before opening a PR.

## Checking the docs

```sh
python3 dev/check_docs_api.py         # every name in docs/ and README exists in src/
python3 dev/check_guide_snippets.py   # the migration guide claims only what tests assert
```

The first one exists because four widget sections had been describing an API
that no longer existed; a name check catches that and a human reading does not.

## Checking the terminal is handed back

```sh
python3 dev/pty_cleanup_check.py
```

Needs a real terminal device, so it cannot live in `gleam test`. It ends an app
four ways — its own loop, `kill -9`, and SIGINT under `+B` and `+Bd` — and
reads back what arrived on the terminal.

## Tests

- Add unit/snapshot tests under `test/` for behavior you change.
- Property tests for `geometry` when touching layout math.
- Erlang-only loop tests use `@target(erlang)` (see `test/app_loop_test.gleam`).

## Demos

Run from repo root:

```sh
gleam run -m etui_showcase
gleam run -m etui_filebrowser
gleam run --target javascript -m etui_js_smoke
```

## Publishing
Contributors do not need to run `gleam publish`.

## Unicode width checks

`gleam test` runs an offline oracle for every Unicode 16 emoji variation
sequence against text measurement, direct buffer writes and bulk fills on
both targets. Expected widths are generated from official Unicode data and
our documented VS15 policy, independently of the production width table.

```sh
python3 dev/generate_emoji_fixture.py
python3 dev/check_unicode_mutations.py
```

The generator downloads pinned Unicode sources and verifies their checksums.
Regeneration should leave the fixture unchanged unless the data or policy is
being deliberately updated. Unicode data uses the
[Unicode data license](https://www.unicode.org/license.txt).

The mutation check copies the current sources, tests and build cache to a
temporary directory, then introduces specific selector, table, segmentation
and clipping regressions. Only test assertion failures count as detected
mutations. A surviving mutation, compilation failure, stale replacement or
timeout fails the command. This is a targeted regression check, not a general
mutation-testing engine; expanding its mutation list requires review.
