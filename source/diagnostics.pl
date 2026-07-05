:- module(diagnostics, [
  message_text/2,
  reason_text/2,
  type_text/2,
  print_analysis_error/1
]).

/*  diagnostics.pl  --  Rendering compiler errors as human-readable text.

    The SINGLE place a parse-diagnostic tag, an analyser error reason, or a
    resolved type becomes prose, shared by both front ends:

      * the LSP server (`syntax/lsp.pl`) puts the text in
        `publishDiagnostics` messages;
      * the batch CLI (`compiler.pl:compile_file/1`) prints it to standard
        error via `print_analysis_error/1`.

    Keeping the wording here means an editor squiggle and a terminal build
    failure always describe the same error the same way.
*/

:- set_prolog_flag(double_quotes, chars).

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(format)).
:- use_module(module_paths, [read_source_chars/2]).

% ---------------------------------------------------------------------------
% CLI reporting
% ---------------------------------------------------------------------------

%% print_analysis_error(+Reason).
%
% Write an `analysis_error` payload to standard error as one or more
% human-readable lines.  Syntax errors carry a char-offset span; when the
% offending module's source is readable the offset is shown as `line:column`
% (1-based), otherwise as a raw offset.  Always succeeds.
print_analysis_error(syntax_errors(Module, Diagnostics)) :- !,
  ( read_source_chars(Module, Text) -> true ; Text = none ),
  print_syntax_diagnostics(Diagnostics, Module, Text).
print_analysis_error(syntax_errors(Diagnostics)) :- !,
  print_syntax_diagnostics(Diagnostics, none, none).
print_analysis_error(Reason) :-
  reason_text(Reason, Msg),
  format(user_error, "error: ~s~n", [Msg]).

print_syntax_diagnostics([], _Module, _Text).
print_syntax_diagnostics([diagnostic(Start, _End, What) | Diagnostics], Module, Text) :-
  message_text(What, Msg),
  ( Text \== none, offset_line_column(Text, Start, Line, Column) ->
      format(user_error, "~s:~d:~d: error: ~s~n", [Module, Line, Column, Msg])
  ; Module \== none ->
      format(user_error, "~s: error at offset ~d: ~s~n", [Module, Start, Msg])
  ; format(user_error, "error at offset ~d: ~s~n", [Start, Msg])
  ),
  print_syntax_diagnostics(Diagnostics, Module, Text).

% A char offset as a 1-based line:column position within the source text.
offset_line_column(Text, Offset, Line, Column) :-
  offset_line_column_(Text, Offset, 1, 1, Line, Column).

offset_line_column_(_Text, 0, Line, Column, Line, Column) :- !.
offset_line_column_([], _Remaining, Line, Column, Line, Column) :- !.
offset_line_column_([Ch | Cs], Remaining, Line0, Column0, Line, Column) :-
  Remaining1 is Remaining - 1,
  ( Ch == '\n' -> Line1 is Line0 + 1, Column1 = 1
  ; Line1 = Line0, Column1 is Column0 + 1
  ),
  offset_line_column_(Cs, Remaining1, Line1, Column1, Line, Column).

% ---------------------------------------------------------------------------
% Message text
% ---------------------------------------------------------------------------

% Render a parse-diagnostic payload (expected(X), unexpected_token, ...) to text.
message_text(expected(X), Msg)        :- !, atom_chars(X, XC), append("expected ", XC, Msg).
message_text(expected_expression, "expected expression") :- !.
message_text(expected_pattern, "expected pattern") :- !.
message_text(expected_type, "expected type") :- !.
message_text(expected(else), "expected `else`") :- !.
message_text(unexpected_token, "unexpected token") :- !.
message_text(opaque_alias_removed,
             "`opaque` takes a variant body; for an FFI type declare `type Name` with no body") :- !.
message_text(Other, Msg) :- atom_chars(Other, Msg).

% Render an analyser error reason to a human message.  The common reasons get a
% tailored message; anything else falls back to the reason's functor name so no
% error is ever swallowed silently.
reason_text(type_mismatch(T1, T2), Msg) :- !,
  type_text(T1, N1), type_text(T2, N2),
  ( N1 == N2 ->
      % Same rendering on both sides (e.g. two distinct type parameters that
      % happen to share a name): say so rather than "A vs A".
      append("type mismatch: ", N1, P1), append(P1, " vs a different ", P2), append(P2, N2, Msg)
  ; append("type mismatch: ", N1, P1), append(P1, " vs ", P2), append(P2, N2, Msg)
  ).
reason_text(unbound_variable(Name), Msg) :- !,
  name_chars(Name, NC), append("unbound variable `", NC, P), append(P, "`", Msg).
reason_text(unknown_constructor(Name), Msg) :- !,
  name_chars(Name, NC), append("unknown constructor `", NC, P), append(P, "`", Msg).
reason_text(undeclared_type(Name), Msg) :- !,
  name_chars(Name, NC), append("undeclared type `", NC, P), append(P, "`", Msg).
reason_text(name_not_exported(Path, Name), Msg) :- !,
  name_chars(Name, NC), name_chars(Path, PC),
  append("`", NC, P1), append(P1, "` is not exported by `", P2),
  append(P2, PC, P3), append(P3, "`", Msg).
reason_text(occurs_check(_), "cannot construct an infinite type") :- !.
reason_text(polymorphic_type_escapes(anonymous), "a polymorphic type would escape its scope") :- !.
reason_text(polymorphic_type_escapes(Name), Msg) :- !,
  name_chars(Name, NC), append("type parameter `", NC, P),
  append(P, "` would escape its scope", Msg).
reason_text(non_exhaustive_match(_, _), "non-exhaustive match") :- !.
reason_text(import_cycle(Module), Msg) :- !,
  name_chars(Module, MC), append("import cycle through `", MC, P), append(P, "`", Msg).
reason_text(cannot_read_module(Module), Msg) :- !,
  name_chars(Module, MC), append("cannot read module `", MC, P), append(P, "`", Msg).
reason_text(missing_module(Module), Msg) :- !,
  name_chars(Module, MC), append("missing module `", MC, P), append(P, "`", Msg).
reason_text(unknown_import(Path, Name), Msg) :- !,
  name_chars(Name, NC), name_chars(Path, PC),
  append("`", NC, P1), append(P1, "` is not defined by `", P2),
  append(P2, PC, P3), append(P3, "`", Msg).
reason_text(forward_reference_outside_function(Name), Msg) :- !,
  name_chars(Name, NC), append("`", NC, P1),
  append(P1, "` is referenced before its definition (only legal inside a function body)", Msg).
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
%   skolem(Id, _, Name)                                `Name` (rigid; `!Id` if nameless)
% ---------------------------------------------------------------------------
type_text(Type, Chars) :- phrase(tt(Type), Chars), !.
type_text(_Type, "?").

tt(number)  --> "number".
tt(boolean) --> "boolean".
tt(string)  --> "string".
tt(unknown) --> "?".
tt(unification_variable(Id)) --> "?", emit_num(Id).
tt(skolem(Id, _, anonymous)) --> !, "!", emit_num(Id).
tt(skolem(_, _, Name))       --> emit_name(Name).
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
