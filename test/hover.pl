:- module(hover, [hover_results/1]).

/*  test/hover.pl  --  LSP hover regression suite.

    Drives `lsp/queries.pl`'s `hover_at/3` directly (bypassing JSON-RPC),
    rendering a semantic hover through `diagnostics:type_text/3` exactly like
    `lsp/lsp.pl`'s `hover_contents/2` does, and comparing against an expected
    shape. Each case gets its own `init_db/0` and file key, so cases never
    share incremental-engine state with each other -- an inline-fixture suite
    (like `test/errors.pl`), not a file-fixture one (like `test/golden.pl`),
    since hover cases are small, self-contained snippets.
*/

:- use_module(library(lists)).
:- use_module('../lsp/queries', [init_db/0, set_input/2, query/2]).
:- use_module('../source/diagnostics', [type_text/3]).

hover_results(Results) :-
  findall(Result, hover_check(Result), CaseResults),
  coverage_result(CoverageResult),
  edit_invalidation_result(EditResult),
  append(CaseResults, [CoverageResult, EditResult], Results).

% ---------------------------------------------------------------------------
% hover_case(Name, Source, TargetSubstring, Expected).
%
% The cursor is the offset of the FIRST occurrence of `TargetSubstring` in
% `Source`. `Expected` is one of:
%   text(Chars)      -- a semantic hover's rendered text must equal this
%   contains(Chars)  -- hover text (semantic or syntax) must contain this
%   null             -- hover_at must yield `none`
%   diagnostic       -- hover must be an error(_) entry
% ---------------------------------------------------------------------------

hover_case(number_literal, "x = 5\n", "5", text("number")).
hover_case(boolean_literal, "x = true\n", "true", text("boolean")).
hover_case(string_literal, "x = 'hi'\n", "'hi'", text("string")).

hover_case(annotated_function_declaration,
           "f = (x: number): number x\n", "f", text("(number): number")).
hover_case(annotated_function_parameter,
           "f = (x: number): number x\n", "x: number", text("number")).
hover_case(partially_annotated_function,
           "f = (x: number) x\n", "f", text("(number): number")).
hover_case(unannotated_function_declaration,
           "f = (x) x\n", "f", contains(": ")).
hover_case(named_generic_function,
           "identity = <A>(x: A): A x\n", "identity", text("<A>(A): A")).
hover_case(bounded_generic_function,
           "public type Logger = {\n  info: (number): number\n}\npublic type Named = {\n  tag: number\n}\nopaque module Combo: Logger + Named = {\n  public info = (n) n + 1\n  public tag = 5\n}\npublic identity = <A: Logger + Named>(x: A): A x\npublic result = identity(Combo)\n",
           "identity", contains("<A: ")).

hover_case(local_shadowing,
           "x = 1\nf = (x: string) x\n", "x: string", text("string")).

hover_case(constructor_use,
           "type Box = Box(number)\nb = Box(5)\n", "Box(5)", text("(number): Box")).

% A tagged-union declaration's OWN name shows its constructors, quantified
% over its own type parameters exactly like a generic function's name does
% (`<A>Body`, no space -- see `named_generic_function` above) -- a nullary
% constructor (`None`) renders bare, a non-generic union's name has no `<>`
% header at all.
hover_case(variant_declaration_name,
           "public type Optional<A> = Some(A) | None\n", "Optional", text("<A>Some(A) | None")).
hover_case(nongeneric_variant_declaration_name,
           "type Bool2 = True | False\n", "Bool2", text("True | False")).

% Record literals label a member with `=`, not `:` (`:` is reserved for type
% annotations) -- see parser.pl's record-expression grammar comment.
hover_case(member_access,
           "v = (x = 1)\nr = v.x\n", "v.x", contains("number")).
% The accessor LABEL itself (not just the whole `v.x` expression) must show
% the field's type -- it used to fall through to the generic ident-token
% syntax help ("Identifier.") because the accessor's own span never got a
% semantic hover entry.
hover_case(member_access_label,
           "v = (x = 1)\nr = v.x\n", "x\n", text("number")).

% A module MEMBER's own declaration name (inside the body, not a use site)
% must show its inferred type -- regardless of the module's own opacity: the
% member's type is known locally while checking the module's body, before
% opacity hides it from the OUTSIDE (see infer.pl's `infer_sequence_item/11`
% `definition_node` clause).
hover_case(opaque_module_member_declaration,
           "public type Logger = {\n  info: (number): number\n}\npublic type Named = {\n  tag: number\n}\nopaque module Combo: Logger + Named = {\n  public info = (n) n + 1\n  public tag = 5\n}\n",
           "tag = 5", text("number")).

% A module's own declaration name renders its row with `{}`, not the `()` a
% plain record value/type uses -- even though both are the same `record_type`
% under the hood (see analyser.pl's `display_module_type/2`); a reference
% site (below, hovering `Counter` as used in `Counter.next(5)`) cannot tell a
% module-typed value apart from a plain record of the same shape, so it keeps
% `()` -- only the DECLARATION site carries the "this is a module" tag.
hover_case(module_binding_name,
           "public module Counter = {\n  start = 0\n  public next = (n) n + 1\n}\n\npublic main = Counter.next(5)\n",
           "Counter =", text("{next: (number): number}")).
hover_case(module_reference_keeps_record_delimiters,
           "public module Counter = {\n  start = 0\n  public next = (n) n + 1\n}\n\npublic main = Counter.next(5)\n",
           "Counter.next(5)", text("(next: (number): number)")).
hover_case(module_member_access_label,
           "public module Counter = {\n  start = 0\n  public next = (n) n + 1\n}\n\npublic main = Counter.next(5)\n",
           "next(5)", text("(number): number")).

hover_case(binary_operator,
           "r = 1 + 2\n", "1 + 2", text("number")).

hover_case(conditional_keyword,
           "r = if true 1 else 2\n", "if", contains("Conditional")).
% Match arms are `| Pattern => Result`, not brace-delimited -- see parser.pl's
% `match_expression`/`match_arms` grammar comment.
hover_case(match_keyword,
           "r = match 1 | x => x\n", "match", contains("Pattern matching")).
hover_case(match_pattern_binding,
           "r = match 1 | x => x\n", "x =>", text("number")).

% The constructor NAME inside a pattern (not just the pattern's bindings)
% gets its own hover, at the union type it destructures -- previously it fell
% through to the generic ident-token syntax help ("Identifier"), because
% lowering discarded the name's own span (see `constructor_pattern_name` and
% `source/syntax/lower.pl`'s `qualified_name_span/2`).
hover_case(constructor_pattern_name,
           "public type Optional<A> = Some(A) | None\npublic isSome = <A>(self: Optional<A>): boolean\n  match self\n  | Some(_) => true\n  | None => false\n",
           "Some(_)", contains("Optional<A>")).

hover_case(assignment,
           "v = (mutable x = 1)\nr = v.x = 2\n", "2", text("number")).

hover_case(type_declaration_keyword,
           "type Box = Box(number)\n", "type", contains("Type declaration")).
% A type declaration's OWN name shows its resolved body -- a module TYPE's
% own name renders with `{}` (matching a module VALUE's own declaration, see
% `module_binding_name` above), while a plain record alias keeps `()`.
hover_case(module_type_declaration_name,
           "public type Named = {\n  tag: number\n}\n", "Named", text("{tag: number}")).
hover_case(record_alias_declaration_name,
           "type Point = (x: number, y: number)\n", "Point", contains("(x: number")).
% A PARAMETRISED alias's own name has no single monomorphic rendering (see
% `validate_declarations/3`'s doc in type_environment.pl), so it is left to
% the generic syntax fallback rather than showing something misleading.
hover_case(parametrised_alias_declaration_name,
           "type Box<T> = (value: T)\n", "Box<", contains("Identifier")).
% An external's own NAME shows its declared type -- `external_node/5` in
% lower.pl carries the name's OWN span (`NameSpan`) separately from the
% whole declaration's `Span` (kept as-is: `infer.pl`'s `item_span/2` still
% needs the WHOLE span to place a `try_item/13` error correctly).
hover_case(external_declaration_name,
           "external log: <A>(A): () = 'console.log'\n", "log", text("<A>(A): ()")).
% Its ANNOTATION is separate, real Group A hover coverage (`seed_externals`
% threads it), so assert on that too.
hover_case(external_declaration,
           "external log: (number): number = 'console.log'\n", "number): number",
           contains("number")).

hover_case(whitespace_is_null,
           "x = 1\n", " = ", null).
% A diagnostic hover entry is recorded at the OUTER item's span (see
% `try_item/13`'s catch branch in infer.pl / `item_span/2`), which usually
% loses to a narrower token/semantic entry within it -- this source's stray
% `)` is malformed enough that the recovering parser treats it as its OWN
% (single-token-wide) top-level item, so its diagnostic entry ties in width
% with the token itself and wins on priority.
hover_case(malformed_syntax_is_diagnostic,
           "x = )\n", ")", diagnostic).

% ---------------------------------------------------------------------------
% Driver
% ---------------------------------------------------------------------------

hover_check(result(Name, Status)) :-
  hover_case(Name, Source, Target, Expected),
  init_db,
  set_input(src("test_hover_case.sl"), Source),
  locate(Source, Target, Offset),
  ( catch(query(hover_at("test_hover_case.sl", Offset), Hover), Caught, Hover = threw(Caught))
  -> true
  ; Hover = bare_failure
  ),
  ( check_expected(Expected, Hover) -> Status = pass ; Status = fail(Hover) ).

% locate(+Source, +Target, -Offset): the 0-based char offset of Target's
% first occurrence in Source.
locate(Source, Target, Offset) :-
  append(Prefix, Rest, Source),
  append(Target, _, Rest), !,
  length(Prefix, Offset).

check_expected(text(Expected), semantic(Type, Names)) :- !,
  type_text(Type, Names, Rendered),
  Rendered == Expected.
check_expected(contains(Substring), semantic(Type, Names)) :- !,
  type_text(Type, Names, Rendered),
  substring(Rendered, Substring).
check_expected(contains(Substring), syntax(_Kind, Help)) :- !,
  substring(Help, Substring).
check_expected(null, none) :- !.
check_expected(diagnostic, error(_)) :- !.

substring(Text, Substring) :-
  append(_, Rest, Text),
  append(Substring, _, Rest), !.

% ---------------------------------------------------------------------------
% Full-coverage sanity check: every non-trivia TOKEN position in a reasonably
% varied sample program must get SOME hover (never `none`) -- the generic
% `node_help`/`token_help` fallback in queries.pl exists exactly to guarantee
% this, so a regression here would mean a node/token kind slipped through
% without even that backstop.
% ---------------------------------------------------------------------------
coverage_result(result(full_coverage_no_silent_gaps, Status)) :-
  Source = "public type Box = {\n  info: (number): number\n}\npublic identity = <A: Box>(x: A): A x\nb = (mutable n = 1)\nr = match b.n | x => x\n",
  init_db,
  set_input(src("coverage_case.sl"), Source),
  length(Source, Len),
  missing_coverage("coverage_case.sl", 0, Len, Gaps),
  ( Gaps == [] -> Status = pass ; Status = fail(missing_hover_at(Gaps)) ).

missing_coverage(_File, Offset, Len, []) :- Offset >= Len, !.
missing_coverage(File, Offset, Len, Gaps) :-
  query(node_at(File, Offset), NodeResult),
  ( NodeResult = found(_, _, token(TokenKind, _, _)), \+ trivia_kind(TokenKind) ->
      query(hover_at(File, Offset), Hover),
      ( Hover == none -> Gaps = [Offset | Rest] ; Gaps = Rest )
  ; Gaps = Rest
  ),
  Offset1 is Offset + 1,
  missing_coverage(File, Offset1, Len, Rest).

trivia_kind(whitespace).
trivia_kind(comment).
trivia_kind(missing).
trivia_kind(eof).

% ---------------------------------------------------------------------------
% Hover recomputes after an edit: no stale reuse of a prior revision's type,
% proving the incremental engine's firewall invalidates `hover_index`/
% `analysis` correctly rather than the LSP layer caching anything itself.
% ---------------------------------------------------------------------------
edit_invalidation_result(result(hover_recomputes_after_edit, Status)) :-
  init_db,
  set_input(src("edit_case.sl"), "x = 1\n"),
  query(hover_at("edit_case.sl", 0), Hover1),
  set_input(src("edit_case.sl"), "x = true\n"),
  query(hover_at("edit_case.sl", 0), Hover2),
  ( Hover1 = semantic(number, _), Hover2 = semantic(boolean, _) ->
      Status = pass
  ; Status = fail(Hover1 - Hover2)
  ).
