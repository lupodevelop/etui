-module(etui_fake_console).
-export([with_replies/2]).

%% Run Action with a fake terminal as the I/O group leader.
%%
%% Successive reads get the given replies: a binary of typed bytes, `eof`, or
%% `failed` for an I/O error. After the last one the terminal stays silent, so
%% a reader that kept asking would block rather than spin, and a regression
%% cannot loop or flood a mailbox.
with_replies(Replies, Action) ->
    Previous = group_leader(),
    Console = spawn(fun() -> serve(Replies) end),
    true = group_leader(Console, self()),
    try
        Action()
    after
        true = group_leader(Previous, self()),
        stop_reader(),
        exit(Console, kill)
    end.

serve(Replies) ->
    receive
        {io_request, From, Tag, {get_chars, _, _, _}} ->
            case Replies of
                [Reply | More] ->
                    From ! {io_reply, Tag, as_chars(Reply)},
                    serve(More);
                [] ->
                    serve([])
            end;
        {io_request, From, Tag, _Other} ->
            From ! {io_reply, Tag, {error, enotsup}},
            serve(Replies)
    end.

as_chars(Bin) when is_binary(Bin) -> binary_to_list(Bin);
as_chars(failed) -> {error, terminated};
as_chars(Other) -> Other.

stop_reader() ->
    case whereis(etui_kbd_reader) of
        undefined -> ok;
        Reader ->
            Monitor = monitor(process, Reader),
            exit(Reader, kill),
            receive {'DOWN', Monitor, process, Reader, _} -> ok end
    end.
