# Terminal state

An app that draws with etui borrows the terminal: raw mode, the alternate
screen, mouse reporting, maybe bracketed paste, usually a hidden cursor.
Every one of those has to be given back, including when the program ends in a
way that runs none of its own code.

## What is sent

`backend.restore_sequence()` is the whole of it, defined once and used by
every target and by the two places that cannot call Gleam at all:

| Sequence | Undoes |
|---|---|
| `?1000l ?1002l ?1003l ?1005l ?1006l ?1007l ?1015l` | mouse reporting, in every encoding a terminal might have accepted |
| `?2026l` | a frame held by synchronized output, if the app died mid-frame |
| `?2004l` | bracketed paste |
| `?1049l` | the alternate screen |
| `?7h` | auto-wrap, which etui turns off to reclaim the last column |
| `0m` | colours and modifiers |
| `?25h` | a hidden cursor |

It is unconditional. Asking a terminal to leave a mode it was never in costs
nothing, and cleanup runs when the state is least trustworthy.

## Ctrl+S and Ctrl+Q

On POSIX the Erlang backend clears `IXON` when it enters raw mode, because
OTP can leave it on (macOS does) and the terminal would then keep Ctrl+S and
Ctrl+Q for itself, pausing output instead of delivering the keys. The setting
the terminal had is read first and put back after `stty sane`, so a shell that
runs with flow control off stays that way. The shell watchdog only runs
`stty sane`, so after a hard kill flow control is whatever `sane` makes it.

## The ways an app ends

**Its own loop.** `terminal.restore` (or `backend.cleanup`, or the end of
`app.run_*`) sends the sequence and leaves raw mode. Nothing else is involved.

**The runtime dies without unwinding** — `erlang:halt`, a crash, `kill -9`.
No Gleam code runs. On the Erlang target an orphan `/bin/sh` process, started
when the app entered raw mode, notices the runtime is gone and writes the
sequence to the terminal device itself. It is a plain POSIX script: no bash,
no fractional-sleep requirement, no assumption that `/tmp` is writable.

It needs a terminal it can name. When `ps` cannot say which terminal the
process belongs to — a pipe, some CI runners, a daemon — no watchdog is
installed, because an orphan is detached from the session and `/dev/tty`
means nothing to it.

**A signal.** On the JavaScript targets raw mode turns ISIG off, so Ctrl+C
arrives as byte 3 and etui delivers it as the key `"ctrl+c"`. On the Erlang
target ISIG stays on (measured on OTP 29): Ctrl+C is a SIGINT, and the BEAM
reserves SIGINT for its own break prompt. It refuses
`os:set_signal(sigint, handle)` unless the VM was started with `+B`, so the app
is left at the break prompt with the terminal still borrowed. An Erlang app
should therefore offer its own quit key and not depend on receiving `"ctrl+c"`.
Ctrl+Q and Ctrl+S do reach it, see the section above.

Start the VM with `+B` if an app should die on SIGINT:

```sh
ERL_FLAGS="+B" gleam run
```

With `+B` the signal terminates the runtime and the watchdog restores the
terminal. Without it, nothing inside the VM can help.

## Checking it

None of this can be tested from the test suite: it needs a real terminal
device, and the interesting paths are the ones where no library code runs.

```sh
python3 dev/pty_cleanup_check.py
```

allocates a pty, gives an app a controlling terminal on it, ends it three
different ways, and reads back what arrived on the terminal.
