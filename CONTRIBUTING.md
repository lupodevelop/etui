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
4. **Docs:** update `docs/` and `doc_snippets_compile_test` in `test/app_loop_test.gleam` when changing public API snippets.
5. **Format:** `gleam format` before opening a PR.

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
