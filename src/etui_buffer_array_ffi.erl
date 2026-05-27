-module(etui_buffer_array_ffi).
-export([new/2, get/2, set/3, fill_string/8, fill_all_rows/8]).
-on_load(init_module/0).

%% Pre-allocate {content, <<B>>, 1} tuples for all 256 bytes on module load.
%% fill_bin receives the table once per row call and uses element/2 (O(1), no alloc)
%% instead of constructing a new Content tuple per character.
init_module() ->
    T = list_to_tuple([{content, <<B>>, 1} || B <- lists:seq(0, 255)]),
    persistent_term:put(etui_ascii_content_table, T),
    ok.

%% Fixed-size array with a default value for unset indices.
%% Erlang `array` is a sparse persistent trie; get/set are O(log10 N)
%% with tiny constants, much cheaper than dict for integer-keyed dense data.

new(Size, Default) ->
    array:new(Size, [{default, Default}]).

get(Index, Arr) ->
    array:get(Index, Arr).

set(Index, Value, Arr) ->
    array:set(Index, Value, Arr).

%% Fill cells in Arr[StartIdx..MaxIdx) from a UTF-8 binary string.
%% Cell tuples are constructed directly, avoids Gleam list/fold overhead.
%%
%% Cell format mirrors buffer.gleam's Gleam types:
%%   {cell, {content, Symbol, Width}, Fg, Bg, Mod, Link}, normal cell
%%   {cell, continuation, Fg, Bg, Mod, <<>>}, wide-char trailer
fill_string(Arr, StartIdx, MaxIdx, Bin, Fg, Bg, Mod, Link) ->
    T = persistent_term:get(etui_ascii_content_table),
    fill_bin(Arr, StartIdx, MaxIdx, Bin, Fg, Bg, Mod, Link, T).

fill_bin(Arr, Idx, MaxIdx, _, _, _, _, _, _) when Idx >= MaxIdx ->
    Arr;
fill_bin(Arr, _, _, <<>>, _, _, _, _, _) ->
    Arr;
%% ASCII printable fast path: cached Content tuple, single Cell alloc per char
fill_bin(Arr, Idx, MaxIdx, <<B, Rest/binary>>, Fg, Bg, Mod, Link, T)
        when B >= 16#20, B < 16#7F ->
    Content = element(B + 1, T),
    Cell = {cell, Content, Fg, Bg, Mod, Link},
    fill_bin(array:set(Idx, Cell, Arr), Idx + 1, MaxIdx, Rest, Fg, Bg, Mod, Link, T);
%% Skip non-printable ASCII (control chars, DEL)
fill_bin(Arr, Idx, MaxIdx, <<B, Rest/binary>>, Fg, Bg, Mod, Link, T) when B < 16#20 ->
    fill_bin(Arr, Idx, MaxIdx, Rest, Fg, Bg, Mod, Link, T);
fill_bin(Arr, Idx, MaxIdx, <<16#7F, Rest/binary>>, Fg, Bg, Mod, Link, T) ->
    fill_bin(Arr, Idx, MaxIdx, Rest, Fg, Bg, Mod, Link, T);
%% Non-ASCII: grapheme cluster segmentation + East Asian width.
%% string:next_grapheme/1 returns [Codepoint|Rest] (single cp)
%% or [[Cp,...]|Rest] (ZWJ sequence / multi-cp cluster).
fill_bin(Arr, Idx, MaxIdx, Bin, Fg, Bg, Mod, Link, T) ->
    case string:next_grapheme(Bin) of
        [] -> Arr;
        [G | Rest] when is_integer(G) ->
            GBin = unicode:characters_to_binary([G]),
            W = cp_width(G),
            Cell = {cell, {content, GBin, W}, Fg, Bg, Mod, Link},
            Arr2 = array:set(Idx, Cell, Arr),
            case W >= 2 of
                true ->
                    Cont = {cell, continuation, Fg, Bg, Mod, <<>>},
                    Arr3 = case Idx + 1 < MaxIdx of
                        true  -> array:set(Idx + 1, Cont, Arr2);
                        false -> Arr2
                    end,
                    fill_bin(Arr3, Idx + 2, MaxIdx, Rest, Fg, Bg, Mod, Link, T);
                false ->
                    fill_bin(Arr2, Idx + 1, MaxIdx, Rest, Fg, Bg, Mod, Link, T)
            end;
        [[FirstCp | _] = GList | Rest] ->
            GBin = unicode:characters_to_binary(GList),
            W = cp_width(FirstCp),
            Cell = {cell, {content, GBin, W}, Fg, Bg, Mod, Link},
            Arr2 = array:set(Idx, Cell, Arr),
            case W >= 2 of
                true ->
                    Cont = {cell, continuation, Fg, Bg, Mod, <<>>},
                    Arr3 = case Idx + 1 < MaxIdx of
                        true  -> array:set(Idx + 1, Cont, Arr2);
                        false -> Arr2
                    end,
                    fill_bin(Arr3, Idx + 2, MaxIdx, Rest, Fg, Bg, Mod, Link, T);
                false ->
                    fill_bin(Arr2, Idx + 1, MaxIdx, Rest, Fg, Bg, Mod, Link, T)
            end
    end.

%% Fill an entire Width×Height buffer from scratch using array:from_list/2.
%% Each row gets the same Bin text. Builds cells as a reversed flat list,
%% reverses once at the end, then constructs the trie in one shot.
%% 3× faster than 60 sequential fill_string calls which rebuild the trie per row.
fill_all_rows(Width, Height, Bin, Fg, Bg, Mod, Link, Default) ->
    T = persistent_term:get(etui_ascii_content_table),
    RevCells = build_buffer_rev(Width, Height, 0, Bin, Fg, Bg, Mod, Link, T, Default, []),
    array:from_list(lists:reverse(RevCells), Default).

build_buffer_rev(_, Height, Row, _, _, _, _, _, _, _, RevAcc) when Row >= Height ->
    RevAcc;
build_buffer_rev(Width, Height, Row, Bin, Fg, Bg, Mod, Link, T, Default, RevAcc) ->
    RevAcc2 = build_row_rev(Width, 0, Bin, Fg, Bg, Mod, Link, T, Default, RevAcc),
    build_buffer_rev(Width, Height, Row + 1, Bin, Fg, Bg, Mod, Link, T, Default, RevAcc2).

%% Produces exactly Width cells, padding with Default if Bin is exhausted.
build_row_rev(Width, Col, _, _, _, _, _, _, Default, RevAcc) when Col >= Width ->
    RevAcc;
build_row_rev(Width, Col, <<>>, Fg, Bg, Mod, Link, T, Default, RevAcc) ->
    fill_rev(Width - Col, Default, RevAcc);
build_row_rev(Width, Col, <<B, Rest/binary>>, Fg, Bg, Mod, Link, T, Default, RevAcc)
        when B >= 16#20, B < 16#7F ->
    Content = element(B + 1, T),
    Cell = {cell, Content, Fg, Bg, Mod, Link},
    build_row_rev(Width, Col + 1, Rest, Fg, Bg, Mod, Link, T, Default, [Cell | RevAcc]);
build_row_rev(Width, Col, <<_B, Rest/binary>>, Fg, Bg, Mod, Link, T, Default, RevAcc) ->
    build_row_rev(Width, Col, Rest, Fg, Bg, Mod, Link, T, Default, RevAcc).

fill_rev(0, _, Acc) -> Acc;
fill_rev(N, V, Acc) -> fill_rev(N - 1, V, [V | Acc]).

%% East Asian Width, mirrors text.gleam's codepoint_cell_width/1.
cp_width(Cp) when Cp < 16#20         -> 0;
cp_width(16#7F)                       -> 0;
cp_width(Cp) when Cp >= 16#0300,
                  Cp =< 16#036F      -> 0;  % combining diacritics
cp_width(Cp) when Cp >= 16#1160,
                  Cp =< 16#11FF      -> 0;  % Hangul medial/final combining
cp_width(Cp) when Cp >= 16#FE00,
                  Cp =< 16#FE0F      -> 0;  % variation selectors
cp_width(Cp) when Cp >= 16#E0100,
                  Cp =< 16#E01EF     -> 0;  % variation selectors ext.
cp_width(16#200B)                     -> 0;
cp_width(16#200C)                     -> 0;
cp_width(16#200D)                     -> 0;
cp_width(16#FEFF)                     -> 0;
cp_width(Cp) when Cp >= 16#1100,
                  Cp =< 16#115F      -> 2;  % Hangul Jamo initial
cp_width(Cp) when Cp >= 16#2E80,
                  Cp =< 16#303E      -> 2;  % CJK Radicals / Kangxi
cp_width(Cp) when Cp >= 16#3041,
                  Cp =< 16#33FF      -> 2;  % Hiragana/Katakana/CJK compat
cp_width(Cp) when Cp >= 16#3400,
                  Cp =< 16#4DBF      -> 2;  % CJK Extension A
cp_width(Cp) when Cp >= 16#4E00,
                  Cp =< 16#9FFF      -> 2;  % CJK Unified Ideographs
cp_width(Cp) when Cp >= 16#A000,
                  Cp =< 16#A4CF      -> 2;  % Yi
cp_width(Cp) when Cp >= 16#AC00,
                  Cp =< 16#D7A3      -> 2;  % Hangul Syllables
cp_width(Cp) when Cp >= 16#F900,
                  Cp =< 16#FAFF      -> 2;  % CJK Compatibility Ideographs
cp_width(Cp) when Cp >= 16#FE30,
                  Cp =< 16#FE4F      -> 2;  % CJK Compatibility Forms
cp_width(Cp) when Cp >= 16#FF00,
                  Cp =< 16#FF60      -> 2;  % Fullwidth Forms
cp_width(Cp) when Cp >= 16#FFE0,
                  Cp =< 16#FFE6      -> 2;  % Fullwidth Signs
cp_width(Cp) when Cp >= 16#1F1E6,
                  Cp =< 16#1F1FF     -> 2;  % Regional Indicators (flags)
cp_width(Cp) when Cp >= 16#1F300,
                  Cp =< 16#1FAFF     -> 2;  % Emoji (misc/pictographs/etc.)
cp_width(Cp) when Cp >= 16#20000,
                  Cp =< 16#2FFFD     -> 2;  % CJK Extensions B–F
cp_width(Cp) when Cp >= 16#30000,
                  Cp =< 16#3FFFD     -> 2;  % CJK Extension G+
cp_width(_)                           -> 1.
