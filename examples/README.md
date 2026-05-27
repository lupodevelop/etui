# Examples (repo only — not published on Hex)

Runnable Gleam apps that depend on **étui**. They live in this repository so you can clone and run immediately; they are **not** included in the Hex package (only `src/` ships).

## Quick pick

| Path | What you learn |
| --- | --- |
| [minimal/](minimal/) | Smallest `run_buffered` app, quit with `q` |
| [counter/](counter/) | Split layout, block + paragraph, space to increment |
| [snippets.md](snippets.md) | Copy-paste fragments (not full projects) |

## Run from clone (path dependency)

```sh
cd examples/minimal
gleam run
```

Each example’s `gleam.toml` uses `etui = { path = "../.." }` (or `../../` from nested paths). After `gleam publish`, you can switch to:

```toml
etui = ">= 1.0.0 and < 2.0.0"
```

## Full demos (library repo)

Larger demos stay under [`dev/`](../dev/) and run from the **repository root**:

```sh
gleam run -m etui_showcase
gleam run -m etui_filebrowser
```

## Widget tours (browser)

Interactive widget reference with ASCII previews and snippets:

**https://etui.altumdream.com/widgets**

API reference: **https://hexdocs.pm/etui**

Guides in markdown: [`docs/`](../docs/)
