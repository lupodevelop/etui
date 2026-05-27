-module(etui_run_ffi).

-export([with_cleanup/2]).

%% Runs Thunk, guaranteeing Cleanup executes on normal return and on any
%% exception (error, throw, or exit). On normal return the thunk's value is
%% propagated; on exception the cleanup runs and the exception re-raises.
%% This gives app.run its crash-restore semantics. Note: a hard erlang:halt
%% bypasses `after`, so abrupt aborts are covered separately by the watchdog
%% in etui_terminal_ffi.
with_cleanup(Thunk, Cleanup) ->
    try
        Thunk()
    after
        Cleanup()
    end.
