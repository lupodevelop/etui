-module(etui_terminal_ffi).

-export([enter_raw/0, exit_raw/0, window_size/0, monotonic_ms/0, read_with_timeout/1,
         install_sigint_cleanup/2, uninstall_sigint_cleanup/0,
         write_cleanup/1, watchdog_script/3]).

%% Everything below that shells out, reads /dev/tty or names a signal is
%% POSIX. On anything else the terminal still has to be handed back, so the
%% escape sequences go out through the ordinary output path and the rest is
%% skipped rather than attempted and failed.
posix() ->
    case os:type() of
        {unix, _} -> true;
        _         -> false
    end.

%% Run something whose failure must not stop cleanup, and say so once rather
%% than eighteen times. `catch Expr` is deprecated in OTP; this is the same
%% intent written the way the language now wants it.
try_(Fun) ->
    try Fun() of
        Value -> Value
    catch
        _:Reason -> {error, Reason}
    end.

%% Enter raw mode via user_drv.  shell:start_interactive({noshell, raw})
%% routes through user_drv's existing prim_tty instance, no second
%% prim_tty:init call, no linked-process conflicts.
enter_raw() ->
    remember_tty_path(),
    case shell:start_interactive({noshell, raw}) of
        ok                      -> ok;
        {error, already_started} -> ok;
        _                       -> ok
    end.

%% Restore cooked mode via stty(1).  Drain buffered mouse/key events first
%% so they don't leak into the shell after we exit raw mode.
%% We entered through shell:start_interactive({noshell, raw}), so restore the
%% shell reader back to cooked mode as well; stty alone is not symmetric.
exit_raw() ->
    stop_reader(),
    drain_input(50),
    try_(fun() -> shell:start_interactive({noshell, cooked}) end),
    try_(fun() -> io:setopts(user, [{echo, true}, {binary, false}]) end),
    stty_sane(),
    ok.

%% stty acts on its standard input, and os:cmd/1 runs a command with stdin
%% redirected from /dev/null: a bare `os:cmd("stty sane")` therefore reset the
%% modes of /dev/null and left the terminal exactly as it was. Point it at the
%% controlling terminal explicitly.
stty_sane() ->
    case posix() of
        false -> ok;
        true ->
            Path = shell_quote(tty_path()),
            try_(fun() ->
                os:cmd("stty sane < " ++ Path ++ " > " ++ Path ++ " 2>/dev/null")
            end),
            ok
    end.

%% Write terminal restore sequences directly to /dev/tty.
%% Fallback to the current group leader if /dev/tty is unavailable.
%%
%% `Seq` comes from etui/backend so that the bytes have one definition; this
%% module used to keep its own copy, and the copy is exactly the kind of thing
%% that stops matching.
write_cleanup(Seq) ->
    write_cleanup_to_tty(Seq, false),
    kill_watchdog(),
    ok.

%% Read and discard all data in the tty input buffer.
%% Stops when the input is closed or no data arrives within TimeoutMs.
%% Kills the reader process on timeout so it doesn't linger.
drain_input(TimeoutMs) ->
    Self = self(),
    Ref = make_ref(),
    Pid = spawn(fun() ->
        Chunk = io:get_chars("", 256),
        Self ! {Ref, Chunk}
    end),
    receive
        {Ref, eof} -> ok;
        {Ref, {error, _}} -> ok;
        {Ref, _} -> drain_input(TimeoutMs)
    after TimeoutMs ->
        exit(Pid, kill),
        ok
    end.

%% Install a SIGINT handler that runs CleanupFun then halts with exit code 130.
%% Call once after entering raw mode.
%%
%% Two paths, and on current OTP only the second one runs.
%%
%% os:set_signal(sigint, handle) is the one that would let this be handled in
%% Erlang. The VM reserves SIGINT for its own break handler and refuses the
%% call with badarg unless it was started with +B; measured on OTP 29. When
%% it does succeed, a watcher process runs the cleanup and halts with 130.
%%
%% Otherwise the shell watchdog below is what is left. It cannot intercept
%% the signal, only notice the runtime dying afterwards, which covers halt,
%% a crash, SIGKILL, and SIGINT on a VM started with +B. It cannot cover a
%% break handler that leaves the VM alive: nothing inside the VM can.
%%
%% In raw mode Ctrl+C is not a signal at all. ISIG is off, so it arrives as
%% byte 3 and etui delivers it as the key "ctrl+c"; this whole path is about
%% a signal sent from somewhere else.
install_sigint_cleanup(CleanupFun, Seq) ->
    case erlang:whereis(etui_sigint_watcher) of
        undefined -> ok;
        Pid -> exit(Pid, replace)
    end,
    reset_watchdog(),
    install_watchdog(Seq),
    SetSignalResult = try_(fun() -> os:set_signal(sigint, handle) end),
    case SetSignalResult of
        ok ->
            %% Erlang-level cleanup watcher.
            %%
            %% Two distinct failure paths need handling:
            %% 1. A real OS SIGINT routed via os:set_signal/2.
            %% 2. The app process dying asynchronously (for example because
            %%    user_drv exits it with reason 'interrupt' before normal
            %%    cleanup runs).
            Owner = self(),
            spawn(fun() ->
                try_(fun() -> erlang:register(etui_sigint_watcher, self()) end),
                receive
                    {signal, sigint} ->
                        try_(CleanupFun),
                        write_cleanup_to_tty(Seq, true),
                        kill_watchdog(),
                        erlang:halt(130);
                    {owner_down, Reason} ->
                        case Reason of
                            normal -> ok;
                            shutdown -> ok;
                            _ ->
                                try_(CleanupFun),
                                write_cleanup_to_tty(Seq, true),
                                kill_watchdog()
                        end;
                    stop ->
                        ok
                end
            end),
            spawn(fun() ->
                erlang:monitor(process, Owner),
                receive_signals(try_(fun() -> erlang:whereis(etui_sigint_watcher) end))
            end),
            ok;
        _ ->
            %% OTP 28 noshell: os:set_signal(sigint, handle) can fail.
            %% The watchdog is already installed above and covers abrupt VM exit.
            ok
    end.

receive_signals(Watcher) ->
    receive
        {signal, sigint} ->
            Watcher ! {signal, sigint};
        {'DOWN', _, process, _, Reason} ->
            Watcher ! {owner_down, Reason}
    end.

%% Spawn a shell watchdog that notices the runtime dying and hands the
%% terminal back itself.
%%
%% The parent shell starts an orphan background subshell and exits at once.
%% The Erlang port therefore points at a process that is gone almost
%% immediately, so port_close and the SIGKILL erlang:halt sends are both
%% no-ops on the orphan. The orphan is reparented to launchd or init and
%% outlives anything the VM can do to it, which is the point: it exists for
%% the exits that never reach cleanup code.
%%
%% A flag file separates a normal exit from an abrupt one. kill_watchdog/0
%% creates it before the VM goes away; the orphan finds it and does nothing.
%%
%% /bin/sh and POSIX constructs only. This used to be /bin/bash with $'\x1b'
%% ANSI-C quoting, which is a bash extension: on Alpine, NixOS or a BSD with
%% no bash in /bin the port failed to open and the watchdog silently did not
%% exist. `sleep` rather than `read -t` for the same reason. The escape bytes
%% are octal-escaped one by one, which every POSIX printf understands and
%% which needs no quoting rules to be got right.
install_watchdog(Seq) ->
    case posix() andalso tty_device() =/= undefined of
        false ->
            %% Without a terminal device to name, the orphan has nowhere to
            %% write: it is detached from the session, so /dev/tty resolves to
            %% nothing for it. Installing it anyway printed
            %% "/bin/sh: /dev/tty: Device not configured" into the session it
            %% was supposed to be repairing.
            ok;
        true ->
            install_watchdog_posix(Seq)
    end.

install_watchdog_posix(Seq) ->
    Token = erlang:unique_integer([positive, monotonic]),
    persistent_term:put({?MODULE, watchdog_token}, Token),
    Flag = flag_path(Token),
    Script = watchdog_script_with_flag(Seq, os:getpid(), tty_device(), Flag),
    spawn(fun() ->
        case try_(fun() -> open_port(
            {spawn_executable, "/bin/sh"},
            [{args, ["-c", Script]}, binary, exit_status]
        ) end) of
            Port when is_port(Port) ->
                try_(fun() -> erlang:register(etui_watchdog_owner, self()) end),
                watchdog_loop(Port, Flag);
            _ ->
                ok
        end
    end).

%% The script itself, as a pure function of the three things it needs, so it
%% can be read and checked without a terminal to run it against.
watchdog_script(Seq, Pid0, TTY0) ->
    watchdog_script_with_flag(Seq, Pid0, TTY0, flag_path(0)).

watchdog_script_with_flag(Seq, Pid0, TTY0, Flag) ->
    Pid = unicode:characters_to_list(Pid0),
    TTYPath = shell_quote(unicode:characters_to_list(TTY0)),
    Inner =
        "trap '' INT HUP TERM" ++
        "; P=" ++ Pid ++
        "; F=" ++ shell_quote(Flag) ++
        %% Fractional sleep is not POSIX; where it is rejected the fallback
        %% keeps this a polling loop rather than a busy one.
        "; while kill -0 \"$P\" 2>/dev/null; do sleep 0.05 2>/dev/null || sleep 1; done" ++
        "; [ -f \"$F\" ] && { rm -f \"$F\"; exit 0; }" ++
        "; printf '" ++ octal_escape(Seq) ++ "'" ++
        " 2>/dev/null > " ++ TTYPath ++
        "; stty sane < " ++ TTYPath ++ " > " ++ TTYPath ++ " 2>/dev/null",
    %% Outer shell: launch the orphan and exit immediately. Returned as a
    %% binary so the same value reads as a String from Gleam.
    unicode:characters_to_binary("(" ++ Inner ++ ") &").

%% Every byte as \NNN. Portable across printf implementations and immune to
%% the shell quoting of whatever the sequence happens to contain.
octal_escape(Seq) ->
    Bin = unicode:characters_to_binary(Seq),
    lists:flatten([io_lib:format("\\~3.8.0b", [B]) || B <- binary_to_list(Bin)]).

%% The flag file lives where the system says temporary files go. /tmp is not
%% writable everywhere, and TMPDIR is what a sandboxed macOS process gets.
%%
%% One file per watchdog, not one per runtime. An app that enters and leaves
%% the terminal more than once installs a watchdog each time, and with a
%% shared name the older orphan could consume the flag meant for the newer
%% one: both would then read "this was a clean exit" and neither would put
%% the terminal back, which is the one thing this whole mechanism is for.
flag_path(Token) ->
    Dir = case os:getenv("TMPDIR") of
        false -> "/tmp";
        "" -> "/tmp";
        T -> string:trim(T, trailing, "/")
    end,
    Dir ++ "/etui_cleanup_" ++ os:getpid() ++ "_" ++ integer_to_list(Token).

%% The token of the watchdog currently installed, if any.
current_token() ->
    persistent_term:get({?MODULE, watchdog_token}, undefined).

watchdog_loop(Port, Flag) ->
    receive
        stop ->
            %% Normal cleanup: create flag so orphan exits without firing.
            try_(fun() -> file:write_file(Flag, <<>>) end),
            try_(fun() -> port_close(Port) end);
        {Port, _} ->
            watchdog_loop(Port, Flag)
    end.

%% Tell the current watchdog that this was a clean exit: the flag file says
%% so, and the owner closes the port.
kill_watchdog() ->
    case current_token() of
        undefined -> ok;
        Token -> try_(fun() -> file:write_file(flag_path(Token), <<>>) end)
    end,
    case erlang:whereis(etui_watchdog_owner) of
        undefined -> ok;
        Pid -> Pid ! stop
    end.

%% Stand down any watchdog left from an earlier entry into raw mode before
%% installing the next one, so two never watch the same runtime.
reset_watchdog() ->
    case erlang:whereis(etui_watchdog_owner) of
        undefined -> ok;
        Pid ->
            Pid ! stop,
            wait_for_exit(Pid, 200)
    end,
    persistent_term:erase({?MODULE, watchdog_token}),
    ok.

wait_for_exit(_Pid, Remaining) when Remaining =< 0 -> ok;
wait_for_exit(Pid, Remaining) ->
    case erlang:is_process_alive(Pid) of
        false -> ok;
        true ->
            timer:sleep(5),
            wait_for_exit(Pid, Remaining - 5)
    end.

%% Restore default SIGINT behaviour and stop the watcher/watchdog.
uninstall_sigint_cleanup() ->
    try_(fun() -> os:set_signal(sigint, default) end),
    case erlang:whereis(etui_sigint_watcher) of
        undefined -> ok;
        Pid -> Pid ! stop
    end,
    ok.

write_cleanup_to_tty(Seq, WithNewline) ->
    Suffix = case WithNewline of
        true -> "\r\n";
        false -> ""
    end,
    Full = unicode:characters_to_list(Seq) ++ Suffix,
    Bin = unicode:characters_to_binary(Full),
    case write_to_device(tty_path(), Bin) of
        ok ->
            ok;
        error ->
            case write_to_device("/dev/tty", Bin) of
                ok -> ok;
                error -> try_(fun() -> io:put_chars(Full) end)
            end
    end.

%% Only ever write the restore bytes to a terminal. tty_path/0 guesses from
%% ps(1) output, and a wrong guess used to mean file:write_file/2 created a
%% file full of escape codes wherever the guess pointed.
write_to_device(Path, Bin) ->
    case file:read_link_info(Path) of
        {ok, Info} when element(3, Info) =:= device ->
            case try_(fun() -> file:write_file(Path, Bin) end) of
                ok -> ok;
                _ -> error
            end;
        _ ->
            error
    end.

remember_tty_path() ->
    case detect_tty_path() of
        {ok, Path} ->
            persistent_term:put({?MODULE, tty_path}, Path);
        error -> ok
    end.

%% The terminal device this process is attached to, or `undefined` when there
%% is no way to name one. Callers that can fall back to the ordinary output
%% path use tty_path/0; the watchdog, which cannot, asks for this.
tty_device() ->
    case persistent_term:get({?MODULE, tty_path}, undefined) of
        undefined ->
            case detect_tty_path() of
                {ok, Path} ->
                    persistent_term:put({?MODULE, tty_path}, Path),
                    Path;
                error -> undefined
            end;
        Path -> Path
    end.

tty_path() ->
    case tty_device() of
        undefined -> "/dev/tty";
        Path -> Path
    end.

detect_tty_path() ->
    %% os:cmd/1 runs the command with stdin redirected from /dev/null, so
    %% `tty` is not reliable here. Ask ps(1) for the controlling terminal
    %% instead, and ask about the parent too: a runtime started without a
    %% controlling terminal of its own is usually the child of a shell that
    %% has one, and that shell's terminal is the one the user is looking at.
    case ps_tty(os:getpid()) of
        {ok, Path} -> {ok, Path};
        error ->
            case ps_ppid(os:getpid()) of
                {ok, Parent} -> ps_tty(Parent);
                error -> error
            end
    end.

ps_tty(Pid) ->
    case try_(fun() -> string:trim(os:cmd("ps -o tty= -p " ++ Pid)) end) of
        TTY when is_list(TTY) -> normalise_tty_path(TTY);
        _ -> error
    end.

ps_ppid(Pid) ->
    case try_(fun() -> string:trim(os:cmd("ps -o ppid= -p " ++ Pid)) end) of
        "" -> error;
        PPid when is_list(PPid) ->
            case string:to_integer(PPid) of
                {N, _} when is_integer(N), N > 1 -> {ok, integer_to_list(N)};
                _ -> error
            end;
        _ -> error
    end.

normalise_tty_path("") ->
    error;
normalise_tty_path([$?|_]) ->
    error;
normalise_tty_path("not a tty") ->
    error;
normalise_tty_path("/dev/" ++ _ = Path) ->
    {ok, Path};
normalise_tty_path(TTY) ->
    {ok, "/dev/" ++ TTY}.

shell_quote(Path) ->
    "'" ++ lists:flatten(string:replace(Path, "'", "'\"'\"'", all)) ++ "'".

%% Monotonic clock in milliseconds, for throttling window_size/0 polls.
monotonic_ms() ->
    erlang:monotonic_time(millisecond).

window_size() ->
    case io:columns() of
        {ok, Cols} ->
            case io:rows() of
                {ok, Rows} ->
                    {ok, {Cols, Rows}};
                _ ->
                    {error, could_not_get_window_size}
            end;
        _ ->
            {error, could_not_get_window_size}
    end.

%% Non-blocking read via persistent actor.
read_with_timeout(TimeoutMs) ->
    ensure_reader(self()),
    receive
        {etui_input, Bin} -> {ok, Bin};
        {etui_input_closed} -> {error, input_closed}
    after TimeoutMs ->
        {error, read_timeout}
    end.

ensure_reader(Owner) ->
    case erlang:whereis(etui_kbd_reader) of
        undefined ->
            Pid = spawn(fun() -> reader_loop(Owner) end),
            try_(fun() -> erlang:register(etui_kbd_reader, Pid) end);
        _ -> ok
    end.

%% eof and {error, _} are answers that never change: asking again gets the same
%% one at once, forever. Report it a single time and let the process end.
reader_loop(Owner) ->
    case io:get_chars("", 128) of
        eof -> Owner ! {etui_input_closed};
        {error, _} -> Owner ! {etui_input_closed};
        Raw ->
            Owner ! {etui_input, to_binary(Raw)},
            reader_loop(Owner)
    end.

stop_reader() ->
    case erlang:whereis(etui_kbd_reader) of
        undefined -> ok;
        Pid -> exit(Pid, kill)
    end.

to_binary(Raw) ->
    case Raw of
        eof                 -> <<>>;
        B when is_binary(B) -> B;
        L when is_list(L)   ->
            case unicode:characters_to_binary(L) of
                Encoded when is_binary(Encoded) -> Encoded;
                _                               -> iolist_to_binary(L)
            end;
        _                   -> <<>>
    end.
