:- module(lsp, [serve/0, serve_streams/2]).

/*  lsp/lsp.pl  --  JSON-RPC Language Server Protocol loop.
    ========================================================================

    The last mile: an event loop that turns editor messages into queries on the
    incremental engine (`queries.pl`) and sends results back, over JSON-RPC.

    LAYERS
      * FRAMING   -- each message is `Content-Length: N\r\n\r\n` + N chars of JSON.
      * JSON      -- `library(serialization/json)`'s `json_chars//1` (bidirectional).
                     Value terms: pairs([Key-Value,..]) (object) | list([..]) |
                     string(Chars) | number(N) | boolean(true|false) | null.
      * DISPATCH  -- on `method`: initialize, textDocument/{didOpen,didChange,
                     didClose,hover,semanticTokens/full}, shutdown, exit.

    HOW IT USES THE ENGINE
      didOpen / didChange  -> set_input(src(Uri), Text)   (ticks the revision)
                           -> query(diagnostics(Uri))     -> publishDiagnostics
      hover                -> position -> the type of the enclosing definition
      semanticTokens/full  -> query(semantic_tokens(Uri)) -> delta-encoded ints
    Because `set_input` only bumps the revision and the Salsa firewall recomputes
    just the affected queries, the server stays responsive per keystroke.

    POSITION MODEL
      LSP positions are {line, character}, 0-based; the engine uses absolute char
      offsets, so the loop converts at the boundary using the document text.
      (LSP `character` is a UTF-16 code unit; a char count suffices for the
      BMP-only fixtures here -- a production server would index UTF-16 units.)
*/

:- set_prolog_flag(double_quotes, chars).

:- use_module(library(lists)).
:- use_module(library(serialization/json), [json_chars//1]).
:- use_module('queries', [init_db/0, set_input/2, query/2]).
:- use_module('../source/syntax/semantic_tokens', [token_type/2]).
:- use_module('../source/module_paths', [canonical_chars/2]).
:- use_module('../source/diagnostics', [message_text/2, reason_text/2, type_text/2]).

% ===========================================================================
% Object accessors over the json_chars/1 term shape.
% ===========================================================================

get(pairs(Pairs), Key, Value) :- member(string(K)-Value, Pairs), K == Key.
get_str(Object, Key, Chars)   :- get(Object, Key, string(Chars)).
get_num(Object, Key, Number)  :- get(Object, Key, number(Number)).

% ===========================================================================
% Message framing over a stream.
% ===========================================================================

read_message(In, Message) :-
  read_headers(In, none, Length),
  ( Length == eof -> Message = end_of_file
  ; read_n(In, Length, Body), once(phrase(json_chars(Message), Body)) ).

read_headers(In, Acc, Length) :-
  read_line(In, Line),
  ( Line == eof             -> Length = eof
  ; Line == []              -> Length = Acc               % blank line ends headers
  ; content_length(Line, N) -> read_headers(In, N, Length)
  ; read_headers(In, Acc, Length) ).                       % ignore other headers

% A header line, CRLF- or LF-terminated, without its terminator.
read_line(In, Result) :-
  get_char(In, C),
  ( C == end_of_file -> Result = eof
  ; C == '\n'        -> Result = []
  ; C == '\r'        -> read_line(In, _DropLF), Result = []
  ; read_line(In, Rest), ( Rest == eof -> Result = [C] ; Result = [C | Rest] ) ).

content_length(Line, N) :-
  append("Content-Length: ", NumberChars, Line),
  number_chars(N, NumberChars).

read_n(_In, 0, []) :- !.
read_n(In, K, [C | Cs]) :-
  K > 0, get_char(In, C), C \== end_of_file, K1 is K - 1, read_n(In, K1, Cs).

write_message(Out, Value) :-
  phrase(json_chars(Value), Body),
  length(Body, N), number_chars(N, NChars),
  append("Content-Length: ", NChars, H1),
  append(H1, "\r\n\r\n", Header),
  put_chars(Out, Header), put_chars(Out, Body),
  flush_output(Out).

put_chars(_Out, []) :- !.
put_chars(Out, [C | Cs]) :- put_char(Out, C), put_chars(Out, Cs).

% ===========================================================================
% The loop.
% ===========================================================================

serve :- current_input(In), current_output(Out), serve_streams(In, Out).

serve_streams(In, Out) :-
  init_db,
  loop(In, Out).

loop(In, Out) :-
  read_message(In, Message),
  ( Message == end_of_file -> true
  ; handle(Message, Out), loop(In, Out) ).

handle(Message, Out) :-
  get_str(Message, "method", MethodChars), !,
  atom_chars(Method, MethodChars),
  ( get_num(Message, "id", Id) -> Request = id(Id) ; Request = notification ),
  dispatch(Method, Request, Message, Out).
handle(_Message, _Out).                                    % a response / unknown: ignore

dispatch('initialize', id(Id), _Msg, Out) :- !,
  semantic_tokens_capability(SemanticTokens),
  Capabilities = pairs([string("textDocumentSync")-number(1),    % 1 = full sync
                        string("hoverProvider")-boolean(true),
                        string("diagnosticProvider")-boolean(true),
                        string("semanticTokensProvider")-SemanticTokens]),
  respond(Out, Id, pairs([string("capabilities")-Capabilities])).
dispatch('initialized', _Req, _Msg, _Out) :- !.
dispatch('shutdown', id(Id), _Msg, Out) :- !, respond(Out, Id, null).
dispatch('exit', _Req, _Msg, _Out) :- !, halt.

dispatch('textDocument/didOpen', _Req, Msg, Out) :- !,
  get(Msg, "params", Params), get(Params, "textDocument", Doc),
  get_str(Doc, "uri", Uri), get_str(Doc, "text", Text),
  update_document(Uri, Text), publish_diagnostics(Out, Uri).
dispatch('textDocument/didChange', _Req, Msg, Out) :- !,
  get(Msg, "params", Params), get(Params, "textDocument", Doc), get_str(Doc, "uri", Uri),
  get(Params, "contentChanges", list([Change | _])), get_str(Change, "text", Text),
  update_document(Uri, Text), publish_diagnostics(Out, Uri).
dispatch('textDocument/didClose', _Req, _Msg, _Out) :- !.

dispatch('textDocument/hover', id(Id), Msg, Out) :- !,
  get(Msg, "params", Params),
  get(Params, "textDocument", Doc), get_str(Doc, "uri", Uri),
  get(Params, "position", Pos), get_num(Pos, "line", Line), get_num(Pos, "character", Char),
  hover_response(Uri, Line, Char, Result),
  respond(Out, Id, Result).

dispatch('textDocument/semanticTokens/full', id(Id), Msg, Out) :- !,
  get(Msg, "params", Params),
  get(Params, "textDocument", Doc), get_str(Doc, "uri", Uri),
  semantic_tokens_response(Uri, Result),
  respond(Out, Id, Result).

dispatch(_Method, id(Id), _Msg, Out) :- !, respond(Out, Id, null).   % unimplemented request
dispatch(_Method, notification, _Msg, _Out).                          % unimplemented notification

respond(Out, Id, Result) :-
  write_message(Out, pairs([string("jsonrpc")-string("2.0"),
                            string("id")-number(Id),
                            string("result")-Result])).

notify(Out, Method, Params) :-
  write_message(Out, pairs([string("jsonrpc")-string("2.0"),
                            string("method")-string(Method),
                            string("params")-Params])).

% ===========================================================================
% Wiring to the incremental engine.
% ===========================================================================

% The engine keys documents by FILESYSTEM PATH (so a `use ./dep` resolves to the
% same key whether `dep` is open in the editor or read from disk).  Editors send
% `file://` URIs, so strip that scheme at the boundary; the original URI is kept
% only for the outgoing `publishDiagnostics` notification.
% Strip the `file://` scheme, then rebuild as fresh cons cells: engine keys are
% compared against canonicalised dependency paths (`module_paths`), and a partial
% string vs an equal cons list compares unequal as an `assoc` key.
uri_to_path(Uri, Path) :-
  ( append("file://", Rest, Uri) -> Raw = Rest ; Raw = Uri ),
  canonical_chars(Raw, Path).

update_document(Uri, Text) :- uri_to_path(Uri, Path), set_input(src(Path), Text).

publish_diagnostics(Out, Uri) :-
  uri_to_path(Uri, Path),
  query(src(Path), Text),
  query(diagnostics(Path), Diagnostics),
  diagnostics_json(Diagnostics, Text, Json),
  notify(Out, "textDocument/publishDiagnostics",
         pairs([string("uri")-string(Uri), string("diagnostics")-list(Json)])).

diagnostics_json([], _Text, []).
diagnostics_json([D | Ds], Text, [J | Js]) :-
  diagnostic_json(D, Text, J), diagnostics_json(Ds, Text, Js).

% Parse diagnostics and type errors both reduce to a [Start,End] char span + text.
% Parse diagnostics come from the recovering parser; `error_at` comes from the
% analyser (`analyse_accumulating/5`), which records one per type error instead
% of throwing on the first.
diagnostic_json(diagnostic(Start, End, What), Text, Json) :- !,
  message_text(What, Msg), diag_object(Start, End, Msg, Text, Json).
diagnostic_json(error_at(span(Start, End), Reason), Text, Json) :- !,
  reason_text(Reason, Msg), diag_object(Start, End, Msg, Text, Json).
diagnostic_json(_Other, Text, Json) :- diag_object(0, 0, "diagnostic", Text, Json).

diag_object(Start, End, MessageChars, Text,
            pairs([string("range")-Range,
                   string("message")-string(MessageChars),
                   string("severity")-number(1)])) :-           % 1 = Error
  offset_to_position(Text, Start, StartPos),
  offset_to_position(Text, End, EndPos),
  Range = pairs([string("start")-StartPos, string("end")-EndPos]).

% offset_to_position(+TextChars, +Offset, -pairs([line, character])).
offset_to_position(Text, Offset, pairs([string("line")-number(Line),
                                        string("character")-number(Char)])) :-
  count_position(Text, Offset, 0, 0, Line, Char).

count_position(_Text, 0, Line, Char, Line, Char) :- !.
count_position([], _Remaining, Line, Char, Line, Char) :- !.
count_position([C | Cs], Remaining, Line0, Char0, Line, Char) :-
  Remaining > 0, Remaining1 is Remaining - 1,
  ( C == '\n' -> Line1 is Line0 + 1, Char1 = 0 ; Line1 = Line0, Char1 is Char0 + 1 ),
  count_position(Cs, Remaining1, Line1, Char1, Line, Char).

% ---------------------------------------------------------------------------
% Semantic tokens: colour every leaf via `syntax/semantic_tokens.pl`'s
% classifier over the green tree, delta-encoded per the LSP wire format (each
% token is 5 ints: deltaLine, deltaStartChar (from the PREVIOUS token's start;
% absolute when deltaLine > 0), length, legend-index, modifiers -- always 0,
% no modifiers are used).  `classify/2` already returns tokens in ascending
% `Start` order (see that module's header), so no sort is needed here either.
% ---------------------------------------------------------------------------
semantic_tokens_capability(pairs([string("legend")-Legend, string("full")-boolean(true)])) :-
  legend_names(Names),
  atom_names_json(Names, NameJson),
  Legend = pairs([string("tokenTypes")-list(NameJson), string("tokenModifiers")-list([])]).

% The legend index of a type name IS its position here -- built by walking
% `token_type/2` from 0 up rather than trusting file order, so the legend
% can never silently drift out of sync with the encoder below.
legend_names(Names) :- legend_names(0, Names).
legend_names(I, [Name | Rest]) :- token_type(Name, I), !, I1 is I + 1, legend_names(I1, Rest).
legend_names(_, []).

atom_names_json([], []).
atom_names_json([Name | Names], [string(Chars) | Json]) :-
  atom_chars(Name, Chars), atom_names_json(Names, Json).

semantic_tokens_response(Uri, pairs([string("data")-list(Data)])) :-
  uri_to_path(Uri, Path),
  query(src(Path), Text),
  query(semantic_tokens(Path), Tokens),
  encode_tokens(Tokens, Text, Ints),
  numbers_json(Ints, Data).

numbers_json([], []).
numbers_json([N | Ns], [number(N) | Js]) :- numbers_json(Ns, Js).

encode_tokens(Toks, Text, Ints) :- encode_tokens(Toks, Text, 0, 0, 0, 0, 0, Ints).

encode_tokens([], _Text, _Off, _Line, _Char, _PrevLine, _PrevChar, []).
encode_tokens([tok(Type, S, E) | Rest], Text0, Off0, Line0, Char0, PrevLine0, PrevChar0, Ints) :-
  SkipToStart is S - Off0,
  consume_chars(Text0, SkipToStart, Line0, Char0, Text1, LineS, CharS),
  SkipToEnd is E - S,
  consume_chars(Text1, SkipToEnd, LineS, CharS, Text2, LineE, CharE),
  DeltaLine is LineS - PrevLine0,
  ( DeltaLine =:= 0 -> DeltaChar is CharS - PrevChar0 ; DeltaChar = CharS ),
  Length is E - S,
  token_type(Type, TypeIndex),
  Ints = [DeltaLine, DeltaChar, Length, TypeIndex, 0 | IntsRest],
  encode_tokens(Rest, Text2, E, LineE, CharE, LineS, CharS, IntsRest).

% consume_chars(+Text, +N, +Line0, +Char0, -RestText, -Line, -Char): advance N
% characters through Text (the SAME line/column counting `count_position/6`
% does), returning both the new position and the unconsumed suffix, so the
% next token's scan picks up where this one left off instead of re-scanning
% from the start of the file (each token is amortised O(its own length), not
% O(file length), even over hundreds of tokens).
consume_chars(Text, 0, Line, Char, Text, Line, Char) :- !.
consume_chars([C | Cs], N, Line0, Char0, Rest, Line, Char) :-
  N > 0, N1 is N - 1,
  ( C == '\n' -> Line1 is Line0 + 1, Char1 = 0 ; Line1 = Line0, Char1 is Char0 + 1 ),
  consume_chars(Cs, N1, Line1, Char1, Rest, Line, Char).

% ---------------------------------------------------------------------------
% Hover: the type of the definition at the cursor.  (A fuller server locates the
% exact green-tree node by offset; this returns the enclosing definition's type,
% the common useful case.)
% ---------------------------------------------------------------------------
hover_response(Uri, Line, Char, Result) :-
  uri_to_path(Uri, Path),
  query(src(Path), Text),
  position_to_offset(Text, Line, Char, Offset),
  ( definition_at(Path, Offset, Name, Type) ->
      hover_contents(Name, Type, Result)
  ; Result = null ).

% Resolve the definition/type under the cursor.  PRECISE path: `node_at` gives
% the identifier token the cursor is on (works at a USE site, not only on the
% definition line); if that name is a known top-level definition, report its
% type.  FALLBACK: the older line heuristic (the cursor is somewhere on a
% definition's line but not on its name token -- e.g. on the value).
definition_at(Path, Offset, Name, Type) :-
  query(node_at(Path, Offset), found(_Kind, _Span, token(ident, Name, _))),
  query(type_at(Path, Name), Type),
  Type \== unknown, !.
definition_at(Path, Offset, Name, Type) :-
  query(src(Path), Text),
  offset_to_position(Text, Offset, pairs([string("line")-number(Line) | _])),
  query(program_ast(Path), program_node(Items)),
  member(definition_node(identifier_node(Name, span(S, _)), _, _, _), Items),
  offset_to_position(Text, S, pairs([string("line")-number(Line) | _])), !,
  query(type_at(Path, Name), Type).

position_to_offset(Text, Line, Char, Offset) :- pos_off(Text, Line, Char, 0, Offset).
pos_off(_, 0, Char, Acc, Offset) :- !, Offset is Acc + Char.
pos_off([C | Cs], Line, Char, Acc, Offset) :-
  Line > 0, Acc1 is Acc + 1,
  ( C == '\n' -> Line1 is Line - 1 ; Line1 = Line ),
  pos_off(Cs, Line1, Char, Acc1, Offset).
pos_off([], _Line, _Char, Acc, Acc).

hover_contents(Name, Type, pairs([string("contents")-string(Contents)])) :-
  type_text(Type, TypeText),
  append(Name, " : ", P), append(P, TypeText, Contents).