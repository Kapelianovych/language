:- module(lsp, [serve/0, serve_streams/2]).

/*  source/syntax/lsp.pl  --  JSON-RPC Language Server Protocol loop.
    ========================================================================

    The last mile: an event loop that turns editor messages into queries on the
    incremental engine (`queries.pl`) and sends results back, over JSON-RPC.

    LAYERS
      * FRAMING   -- each message is `Content-Length: N\r\n\r\n` + N chars of JSON.
      * JSON      -- `library(serialization/json)`'s `json_chars//1` (bidirectional).
                     Value terms: pairs([Key-Value,..]) (object) | list([..]) |
                     string(Chars) | number(N) | boolean(true|false) | null.
      * DISPATCH  -- on `method`: initialize, textDocument/{didOpen,didChange,
                     didClose,hover}, shutdown, exit.

    HOW IT USES THE ENGINE
      didOpen / didChange  -> set_input(src(Uri), Text)   (ticks the revision)
                           -> query(diagnostics(Uri))     -> publishDiagnostics
      hover                -> position -> the type of the enclosing definition
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
:- use_module('../module_paths', [canonical_chars/2]).

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
  Capabilities = pairs([string("textDocumentSync")-number(1),    % 1 = full sync
                        string("hoverProvider")-boolean(true),
                        string("diagnosticProvider")-boolean(true)]),
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

% Render a parse-diagnostic payload (expected(X), unexpected_token, ...) to text.
message_text(expected(X), Msg)        :- !, atom_chars(X, XC), append("expected ", XC, Msg).
message_text(expected_expression, "expected expression") :- !.
message_text(expected_pattern, "expected pattern") :- !.
message_text(expected_type, "expected type") :- !.
message_text(expected(else), "expected `else`") :- !.
message_text(unexpected_token, "unexpected token") :- !.
message_text(Other, Msg) :- atom_chars(Other, Msg).

% Render an analyser error reason to a human message.  The common reasons get a
% tailored message; anything else falls back to the reason's functor name so no
% error is ever swallowed silently.
reason_text(type_mismatch(T1, T2), Msg) :- !,
  type_text(T1, N1), type_text(T2, N2),
  append("type mismatch: ", N1, P1), append(P1, " vs ", P2), append(P2, N2, Msg).
reason_text(unbound_variable(Name), Msg) :- !,
  name_chars(Name, NC), append("unbound variable `", NC, P), append(P, "`", Msg).
reason_text(unknown_constructor(Name), Msg) :- !,
  name_chars(Name, NC), append("unknown constructor `", NC, P), append(P, "`", Msg).
reason_text(undeclared_type(Name), Msg) :- !,
  name_chars(Name, NC), append("undeclared type `", NC, P), append(P, "`", Msg).
reason_text(occurs_check(_), "cannot construct an infinite type") :- !.
reason_text(non_exhaustive_match(_, _), "non-exhaustive match") :- !.
reason_text(Reason, Msg) :-                                % generic fallback
  functor(Reason, Name, _), atom_chars(Name, NameChars),
  reason_words(NameChars, Msg).

% Turn a snake_case functor name into spaced words (`function_arity_mismatch` ->
% "function arity mismatch").
reason_words([], []).
reason_words(['_' | Cs], [' ' | Ms]) :- !, reason_words(Cs, Ms).
reason_words([C | Cs], [C | Ms]) :- reason_words(Cs, Ms).

% ---------------------------------------------------------------------------
% Rendering the analyser's resolved types (the SINGLE type representation).
%   number | boolean | string                         base types
%   function_type(Params, Return)                     `(p, ..) -> r`
%   tuple_type(Fields, Tail)                           record `(key: t, .. | ..)`
%       Fields = [tuple_field(Mutability, Key, Type)]; Key = index(N) | label(Cs)
%       Tail   = closed | unification_variable(_)      (open row)
%   type_constructor(Name, Args)                       nominal `Name(a, ..)`
%   unification_variable(Id)                           `?Id` (unsolved)
%   forall_type(_, Body)                               show the body
%   skolem(Id, _)                                      `!Id` (rigid)
% ---------------------------------------------------------------------------
type_text(Type, Chars) :- phrase(tt(Type), Chars), !.
type_text(_Type, "?").

tt(number)  --> "number".
tt(boolean) --> "boolean".
tt(string)  --> "string".
tt(unknown) --> "?".
tt(unification_variable(Id)) --> "?", emit_num(Id).
tt(skolem(Id, _))            --> "!", emit_num(Id).
tt(function_type(Params, Return)) --> "(", tt_seq(Params), ") -> ", tt(Return).
tt(tuple_type(Fields, Tail))      --> "(", tt_fields(Fields), tt_tail(Tail), ")".
tt(type_constructor(Name, []))         --> emit_name(Name).
tt(type_constructor(Name, [A | As]))   --> emit_name(Name), "(", tt_seq([A | As]), ")".
tt(forall_type(_, Body)) --> tt(Body).
tt(_) --> "?".

tt_seq([])            --> [].
tt_seq([T])           --> tt(T).
tt_seq([T, U | Ts])   --> tt(T), ", ", tt_seq([U | Ts]).

tt_fields([])          --> [].
tt_fields([F])         --> tt_field(F).
tt_fields([F, G | Fs]) --> tt_field(F), ", ", tt_fields([G | Fs]).

tt_field(tuple_field(_, Key, Type)) --> tt_key(Key), ": ", tt(Type).

tt_key(label(Name)) --> !, emit_name(Name).
tt_key(index(N))    --> !, emit_num(N).
tt_key(Other)       --> emit_name(Other).

tt_tail(closed)                    --> [].
tt_tail(unification_variable(_))   --> " | ..".
tt_tail(_)                         --> [].

emit_name(Name) --> { name_chars(Name, Cs) }, emit(Cs).
emit_num(N)     --> { number_chars(N, Cs) }, emit(Cs).
emit([])        --> [].
emit([C | Cs])  --> [C], emit(Cs).

% A name in the AST is a char list; base-type tags are atoms -- accept either.
name_chars(Name, Chars) :- ( atom(Name) -> atom_chars(Name, Chars) ; Chars = Name ).

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

% Find the definition whose value/name region contains Offset.  We approximate
% by choosing the definition whose name appears on the cursor's line, then ask
% the engine for that definition's resolved type (`type_at`).
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