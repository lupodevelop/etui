-module(etui_text_ffi).
-export([graphemes/1, next_grapheme/1]).
-on_load(init_module/0).

init_module() ->
    {ok, Pattern} = re:compile(<<"^\\X">>, [unicode]),
    persistent_term:put(etui_grapheme_tail_pattern, Pattern),
    ok.

graphemes(Bin) -> graphemes(Bin, []).
graphemes(Bin, Rev) ->
    case next_grapheme(Bin) of
        done -> lists:reverse(Rev);
        {G, Rest} -> graphemes(Rest, [G | Rev])
    end.

%% OTP can split attached marks after a trailing ZWJ. Use the regex engine's
%% extended cluster rule at that boundary, consistently for text and buffers.
%% https://www.unicode.org/reports/tr29/#Grapheme_Cluster_Boundary_Rules
next_grapheme(Bin) ->
    case string:next_grapheme(Bin) of
        [] -> done;
        [G | Rest] ->
            GBin = case G of
                N when is_integer(N) -> unicode:characters_to_binary([N]);
                _ -> unicode:characters_to_binary(G)
            end,
            case (is_list(G) andalso lists:last(G) =:= 16#200D) of
                true -> joined_cluster(Bin, GBin, Rest);
                false -> {GBin, Rest}
            end
    end.

%% Keep the native result if an older regex Unicode table would shorten it.
joined_cluster(Bin, Native, Rest) ->
    Pattern = persistent_term:get(etui_grapheme_tail_pattern),
    Size = byte_size(Native),
    case re:run(Bin, Pattern, [{capture, first, binary}]) of
        {match, [<<Native:Size/binary, _/binary>> = Full]} ->
            Used = byte_size(Full),
            {Full, binary:part(Bin, Used, byte_size(Bin) - Used)};
        _ -> {Native, Rest}
    end.
