:- module(diagnostics, [
  message_text/2,
  reason_text/2,
  type_text/2,
  type_text/3
]).

/*  diagnostics.pl  --  Rendering compiler errors as human-readable text.

    The SINGLE place a parse-diagnostic tag, an analyser error reason, or a
    resolved type becomes prose, shared by both front ends:

      * the LSP server (`lsp/lsp.pl`) puts the text in
        `publishDiagnostics` messages;
      * the batch CLI (`cli/cli.pl:print_analysis_error/1`) prints it to
        standard error.

    Keeping the wording here means an editor squiggle and a terminal build
    failure always describe the same error the same way.  This module itself
    touches neither a stream nor the filesystem -- see `cli/cli.pl` for where
    `message_text/2` and `reason_text/2` meet an actual `stderr`.
*/

:- set_prolog_flag(double_quotes, chars).

:- use_module(library(dcgs)).
:- use_module(library(lists)).

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
reason_text(duplicate_definition(Name), Msg) :- !,
  name_chars(Name, NC), append("`", NC, P1),
  append(P1, "` is defined more than once in the same scope", Msg).
reason_text(malformed_syntax(_Span), "malformed syntax") :- !.
reason_text(internal_error,
            "internal compiler error: compilation failed without a diagnostic (please report this program)") :- !.
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
%   number | boolean | string                          base types
%   function_type(Params, Return)                      `(p ..): r`
%   record_type(Fields, Tail)                           record `(key: t .. ..)`
%       Fields = [record_field(Mutability, Key, Type)]; Key = index(N) | label(Cs)
%       Tail   = closed | unification_variable(_)      (open row)
%   module_row(Fields, Tail)                            DISPLAY-ONLY: a module's
%       or module type's own row, `{key: t .. ..}` -- same Fields/Tail shape as
%       record_type, never produced by inference/unification itself, only
%       substituted in at a module('s type) declaration's OWN hover entry (see
%       analyser.pl's `display_module_type/2` and type_environment.pl's
%       `validate_declarations/3`) to mark it visually distinct from an
%       ordinary record value/type, which real inference cannot otherwise tell
%       apart from a module's row (both are the exact same `record_type/2`).
%   variant_type(Ctors)                                 DISPLAY-ONLY: a tagged
%       union declaration's OWN constructors, `Ctor(t ..) | Ctor2 | ..` --
%       `Ctors = [ctor_display(Name, FieldTypes)]`, never produced by
%       inference/unification (which only ever sees one CONSTRUCTOR at a
%       time, never "the whole union" as a value type), only substituted in
%       at a variant declaration's OWN hover entry (see type_environment.pl's
%       `validate_declarations/3`), same spirit as `module_row` above.
%   type_constructor(Name, Args)                       nominal `Name<a ..>`
%   unification_variable(Id)                           `_UId` (unsolved)
%   quantified_variable(Id)                            `_QId`, or its declared
%                                                       name/bound if a NAMES
%                                                       table is supplied
%   forall_type(BoundIds, Body)                        `<id ..>Body`
%   skolem(Id, _, Name)                                `Name` (rigid; `_SId` if nameless)
%   intersection_type(Members)                         `M1 + M2 + ..`
%
% `type_text/2` is the plain (non-hover) renderer every existing caller
% already uses -- error messages, etc. -- with no names table, so a
% quantified variable always falls back to its synthetic `_Q<Id>` form.
% `type_text/3` is hover's renderer: `NamesTable` is the self-contained
% `Id - Name - Bound` list `types.pl`'s `quantified_name_table/3` builds
% while the analyser's `Context` is still available (see `analyser.pl`'s
% `finalize_raw_hover_entries/3`) -- by the time hover renders, that Context
% is long gone, so every quantified id's name and bound have to travel WITH
% the resolved type rather than being looked up lazily here.
% ---------------------------------------------------------------------------
type_text(Type, Chars) :- phrase(tt(Type, []), Chars), !.
type_text(_Type, "?").

type_text(Type, NamesTable, Chars) :- phrase(tt(Type, NamesTable), Chars), !.
type_text(_Type, _NamesTable, "?").

tt(number, _Names)                                  --> "number".
tt(boolean, _Names)                                 --> "boolean".
tt(string, _Names)                                  --> "string".
tt(unknown, _Names)                                 --> "?".
tt(unification_variable(Id), _Names)                --> "_U", emit_number(Id).
tt(quantified_variable(Id), Names)                  -->
  ( { memberchk(Id - Name - _Bound, Names), Name \== anonymous } ->
      emit_name(Name)
  ; "_Q", emit_number(Id)
  ).
tt(skolem(Id, _, anonymous), _Names)                --> !, "_S", emit_number(Id).
tt(skolem(_, _, Name), _Names)                      --> emit_name(Name).
tt(function_type(Params, Return), Names)            --> "(", tt_sequence(Params, Names), "): ", tt(Return, Names).
tt(record_type(Fields, Tail), Names)                --> "(", tt_fields(Fields, Names), tt_tail(Tail), ")".
tt(module_row(Fields, Tail), Names)                 --> "{", tt_fields(Fields, Names), tt_tail(Tail), "}".
tt(variant_type(Ctors), Names)                      --> tt_ctors(Ctors, Names).
tt(type_constructor(Name, []), _Names)              --> emit_name(Name).
tt(type_constructor(Name, TypeParameters), Names)   --> emit_name(Name), "<", tt_sequence(TypeParameters, Names), ">".
tt(forall_type(BoundIds, Body), Names)              --> "<", tt_bound_header(BoundIds, Names), ">", tt(Body, Names).
% An intersection `B + C (+ ..)` -- the "membership contract" a bounded
% generic's `<A: B + C>` converts its bound to (see type_environment.pl); no
% special casing was needed for hover's use of it, since a plain `+`-joined
% sequence already reads the same way the source annotation was written.
tt(intersection_type(Members), Names)               --> tt_intersection(Members, Names).
tt(X, Names) --> { format(user_error, "tt fallback hit for: ~q~nNames:~q~n", [X, Names]) }, "?".

% tt_bound_header(+BoundIds, +Names): a forall_type's own header, one bound
% id at a time -- `<A: Logger + Named>` when `Names` has a name/bound for
% that id, `<_Q7>` (the old, synthetic form) when it doesn't (e.g. no
% NamesTable was supplied at all, via plain `type_text/2`).
tt_bound_header([], _Names) --> [].
tt_bound_header([Id], Names) --> !, tt_bound_id(Id, Names).
tt_bound_header([Id | Ids], Names) --> tt_bound_id(Id, Names), " ", tt_bound_header(Ids, Names).

tt_bound_id(Id, Names) -->
  ( { memberchk(Id - Name - Bound, Names), Name \== anonymous } ->
      emit_name(Name),
      ( { Bound \== no_bound } -> ": ", tt(Bound, Names) ; [] )
  ; "_Q", emit_number(Id)
  ).

tt_intersection([], _Names) --> [].
tt_intersection([Member], Names) --> !, tt(Member, Names).
tt_intersection([Member | Members], Names) --> tt(Member, Names), " + ", tt_intersection(Members, Names).

tt_sequence([], _Names)            --> [].
tt_sequence([T], Names)            --> tt(T, Names).
tt_sequence([T, U | Ts], Names)    --> tt(T, Names), " ", tt_sequence([U | Ts], Names).

tt_fields([], _Names)          --> [].
tt_fields([F], Names)          --> tt_field(F, Names).
tt_fields([F, G | Fs], Names)  --> tt_field(F, Names), "\n", tt_fields([G | Fs], Names).

tt_ctors([], _Names)           --> [].
tt_ctors([C], Names)           --> !, tt_ctor(C, Names).
tt_ctors([C | Cs], Names)      --> tt_ctor(C, Names), " | ", tt_ctors(Cs, Names).

tt_ctor(ctor_display(Name, []), _Names)     --> !, emit_name(Name).
tt_ctor(ctor_display(Name, Fields), Names)  --> emit_name(Name), "(", tt_sequence(Fields, Names), ")".

tt_field(record_field(Mutability, Key, Type), Names) --> tt_field_mutability(Mutability), tt_key(Key), ": ", tt(Type, Names).

tt_field_mutability(readonly) --> [].
tt_field_mutability(mutable)  --> "mutable ".

tt_key(label(Name)) --> !, emit_name(Name).
tt_key(index(N))    --> !, emit_number(N).
tt_key(Other)       --> emit_name(Other).

tt_tail(closed)                    --> [].
tt_tail(unification_variable(_))   --> " ..".
tt_tail(_)                         --> [].

emit_name(Name)    --> { name_chars(Name, Cs) }, emit(Cs).
emit_number(N)     --> { number_chars(N, Cs) }, emit(Cs).
emit([])           --> [].
emit([C | Cs])     --> [C], emit(Cs).

% A name in the AST is a char list; base-type tags are atoms -- accept either.
name_chars(Name, Chars) :- ( atom(Name) -> atom_chars(Name, Chars) ; Chars = Name ).
