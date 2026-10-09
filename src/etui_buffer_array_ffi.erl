-module(etui_buffer_array_ffi).
-export([new/2, get/2, set/3, fill_string/6, fill_all_rows/6,
         draft/1, draft_set/3, draft_get/2, commit/1, same/2]).
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

%% Cheap identity test: true when the two are the same physical term, false
%% when they merely might be equal. Callers fall back to a structural compare.
%% erts_debug:same/2 is the pointer comparison; =:= would walk two equal-but-
%% distinct terms in full, which is the work this call exists to avoid.
same(A, B) -> erts_debug:same(A, B).

new(Size, Default) ->
    array:new(Size, [{default, Default}]).

get(Index, Arr) ->
    array:get(Index, Arr).

set(Index, Value, Arr) ->
    array:set(Index, Value, Arr).

%% Batched writes. Erlang's array is already a persistent trie, so a draft is
%% the array itself and these are all identity or a plain set; the distinction
%% exists for the JavaScript side, where a naive copy-on-write set made a full
%% buffer fill quadratic.
draft(Arr) -> Arr.
draft_set(Index, Value, Arr) -> array:set(Index, Value, Arr).
draft_get(Index, Arr) -> array:get(Index, Arr).
commit(Arr) -> Arr.

%% Fill cells in Arr[StartIdx..MaxIdx) from a UTF-8 binary string.
%% Cell tuples are constructed directly, avoids Gleam list/fold overhead.
%%
%% Cell format mirrors buffer.gleam's Gleam types:
%%   {cell, {content, Symbol, Width}, Style, Link}, normal cell
%%   {cell, continuation, Style, <<>>}, wide-char trailer
%% The style is an opaque term here: it arrives already resolved from Gleam
%% and is only ever copied into cells, so this module never looks inside it.
fill_string(Arr, StartIdx, MaxIdx, Bin, St, Link) ->
    T = persistent_term:get(etui_ascii_content_table),
    fill_bin(Arr, StartIdx, MaxIdx, Bin, St, Link, T).

fill_bin(Arr, Idx, MaxIdx, _, _, _, _) when Idx >= MaxIdx ->
    Arr;
fill_bin(Arr, _, _, <<>>, _, _, _) ->
    Arr;
%% ASCII printable fast path: cached Content tuple, single Cell alloc per char
fill_bin(Arr, Idx, MaxIdx, <<B, Rest/binary>>, St, Link, T)
        when B >= 16#20, B < 16#7F ->
    Content = element(B + 1, T),
    Cell = {cell, Content, St, Link},
    fill_bin(array:set(Idx, Cell, Arr), Idx + 1, MaxIdx, Rest, St, Link, T);
%% Skip non-printable ASCII (control chars, DEL)
fill_bin(Arr, Idx, MaxIdx, <<B, Rest/binary>>, St, Link, T) when B < 16#20 ->
    fill_bin(Arr, Idx, MaxIdx, Rest, St, Link, T);
fill_bin(Arr, Idx, MaxIdx, <<16#7F, Rest/binary>>, St, Link, T) ->
    fill_bin(Arr, Idx, MaxIdx, Rest, St, Link, T);
%% Non-ASCII: grapheme cluster segmentation + East Asian width.
%% string:next_grapheme/1 returns [Codepoint|Rest] (single cp)
%% or [[Cp,...]|Rest] (ZWJ sequence / multi-cp cluster).
fill_bin(Arr, Idx, MaxIdx, Bin, St, Link, T) ->
    case string:next_grapheme(Bin) of
        [] -> Arr;
        [G | Rest] ->
            {GBin, FirstCp} = grapheme_parts(G),
            fill_grapheme(Arr, Idx, MaxIdx, Rest, GBin, cp_width(FirstCp),
                          St, Link, T)
    end.

%% Write one grapheme cluster at Idx.
%%
%% A wide grapheme needs two columns. If only one is left before MaxIdx the
%% cell is left blank: writing the glyph anyway made it overflow the clip
%% boundary and shift everything to its right.
fill_grapheme(Arr, Idx, MaxIdx, Rest, _GBin, W, St, Link, T)
        when W >= 2, Idx + 1 >= MaxIdx ->
    fill_bin(Arr, Idx + 1, MaxIdx, Rest, St, Link, T);
fill_grapheme(Arr, Idx, MaxIdx, Rest, GBin, W, St, Link, T)
        when W >= 2 ->
    Cell = {cell, {content, GBin, W}, St, Link},
    Cont = {cell, continuation, St, <<>>},
    Arr2 = array:set(Idx + 1, Cont, array:set(Idx, Cell, Arr)),
    fill_bin(Arr2, Idx + 2, MaxIdx, Rest, St, Link, T);
fill_grapheme(Arr, Idx, MaxIdx, Rest, GBin, W, St, Link, T) ->
    Cell = {cell, {content, GBin, W}, St, Link},
    fill_bin(array:set(Idx, Cell, Arr), Idx + 1, MaxIdx, Rest, St, Link, T).

%% Fill an entire Width×Height buffer from scratch using array:from_list/2.
%% Each row gets the same Bin text. Builds cells as a reversed flat list,
%% reverses once at the end, then constructs the trie in one shot.
%% 3× faster than 60 sequential fill_string calls which rebuild the trie per row.
fill_all_rows(Width, Height, Bin, St, Link, Default) ->
    T = persistent_term:get(etui_ascii_content_table),
    RevCells = build_buffer_rev(Width, Height, 0, Bin, St, Link, T, Default, []),
    array:from_list(lists:reverse(RevCells), Default).

build_buffer_rev(_, Height, Row, _, _, _, _, _, RevAcc) when Row >= Height ->
    RevAcc;
build_buffer_rev(Width, Height, Row, Bin, St, Link, T, Default, RevAcc) ->
    RevAcc2 = build_row_rev(Width, 0, Bin, St, Link, T, Default, RevAcc),
    build_buffer_rev(Width, Height, Row + 1, Bin, St, Link, T, Default, RevAcc2).

%% Produces exactly Width cells, padding with Default if Bin is exhausted.
%% Mirrors fill_bin/7 clause for clause: ASCII fast path, control characters
%% consume no cell, everything else goes through grapheme segmentation.
build_row_rev(Width, Col, _, _, _, _, _Default, RevAcc) when Col >= Width ->
    RevAcc;
build_row_rev(Width, Col, <<>>, _St, _Link, _T, Default, RevAcc) ->
    fill_rev(Width - Col, Default, RevAcc);
%% ASCII printable fast path: cached Content tuple, single Cell alloc per char.
build_row_rev(Width, Col, <<B, Rest/binary>>, St, Link, T, Default, RevAcc)
        when B >= 16#20, B < 16#7F ->
    Content = element(B + 1, T),
    Cell = {cell, Content, St, Link},
    build_row_rev(Width, Col + 1, Rest, St, Link, T, Default, [Cell | RevAcc]);
%% Control characters and DEL occupy no cell.
build_row_rev(Width, Col, <<B, Rest/binary>>, St, Link, T, Default, RevAcc)
        when B < 16#20; B =:= 16#7F ->
    build_row_rev(Width, Col, Rest, St, Link, T, Default, RevAcc);
%% Non-ASCII: grapheme cluster segmentation + East Asian width.
%% Dropping these (the previous catch-all did) silently deleted every CJK and
%% emoji character from a filled buffer, and diverged from the JS backend.
build_row_rev(Width, Col, Bin, St, Link, T, Default, RevAcc) ->
    case string:next_grapheme(Bin) of
        [] ->
            fill_rev(Width - Col, Default, RevAcc);
        [G | Rest] ->
            {GBin, FirstCp} = grapheme_parts(G),
            case cp_width(FirstCp) of
                W when W >= 2, Col + 1 >= Width ->
                    %% No room for the trailing half. Emit a blank rather than
                    %% a wide glyph that would overflow the row.
                    build_row_rev(Width, Col + 1, Rest, St, Link, T,
                                  Default, [Default | RevAcc]);
                W when W >= 2 ->
                    Cell = {cell, {content, GBin, W}, St, Link},
                    Cont = {cell, continuation, St, <<>>},
                    build_row_rev(Width, Col + 2, Rest, St, Link, T,
                                  Default, [Cont, Cell | RevAcc]);
                W ->
                    Cell = {cell, {content, GBin, W}, St, Link},
                    build_row_rev(Width, Col + 1, Rest, St, Link, T,
                                  Default, [Cell | RevAcc])
            end
    end.

%% string:next_grapheme/1 yields a bare codepoint for a single-codepoint
%% cluster and a list for a multi-codepoint one (ZWJ sequence, flag pair).
grapheme_parts(G) when is_integer(G) ->
    {unicode:characters_to_binary([G]), G};
grapheme_parts([FirstCp | _] = GList) ->
    {unicode:characters_to_binary(GList), FirstCp}.

fill_rev(0, _, Acc) -> Acc;
fill_rev(N, V, Acc) -> fill_rev(N - 1, V, [V | Acc]).

%% One width table: text.gleam's. A second copy here drifted once already.
cp_width(Cp) -> 'etui@text':codepoint_cell_width(Cp).
