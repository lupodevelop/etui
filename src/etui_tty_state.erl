-module(etui_tty_state).

-export([init/0, set_raw/1, is_raw_mode/0]).

init() ->
    case ets:whereis(etui_tty_state) of
        undefined ->
            ets:new(etui_tty_state, [named_table, public, set]),
            ets:insert(etui_tty_state, {raw_mode, false});
        _ ->
            ok
    end.

set_raw(IsRaw) ->
    case ets:whereis(etui_tty_state) of
        undefined ->
            ets:new(etui_tty_state, [named_table, public, set]);
        _ ->
            ok
    end,
    ets:insert(etui_tty_state, {raw_mode, IsRaw}).

is_raw_mode() ->
    case ets:lookup(etui_tty_state, raw_mode) of
        [{raw_mode, true}] ->
            true;
        _ ->
            false
    end.
