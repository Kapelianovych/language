:- module(macro_transformation, [
  check_macros/1,
  expand_macros/2,
  % Whole-program (cross-file, module-qualified) entry points used by the loader.
  program_macros/2,
  program_compiler_imports/2,
  macro_table/2,
  check_macro_set/2,
  require_parse_item_import/2,
  macro_key_name/3,
  resolve_macro_body/3,
  resolve_uses/3,
  expand_program_with_table/3
]).

/*  transformation/macro.pl  --  Reader-macro processing.

    This is the compile-time half of the reader-macro feature (see
    `docs/reader-macros.md` and `parser/macro_syntax.pl`).  It will eventually
    both TYPE-CHECK and EXPAND macros; this file currently implements the
    type-checking half.

    TYPE-CHECKING MACRO BODIES  (`check_macros/1`)

      A macro `macro NAME = (p1 .. pn) BODY` is, semantically, an ordinary
      COMPILE-TIME function `(p1 .. pn) -> Ast`.  So rather than build a bespoke
      checker, we DESUGAR each macro to a normal value definition

          NAME = (p1 .. pn): Ast BODY

      (an untyped-parameter lambda whose return is annotated `Ast`) and run the
      EXISTING Hindley-Milner inference (`analyser:analyse_module/5`) over the
      collected definitions.  This gives, for free:
        * parameter-type inference (no annotations needed: `n : number`,
          `source : string`, ...),
        * recursion and mutual reference between macros (a macro is callable as
          a function from another macro body -- that is how `times` recurses),
        * full checking of `match`, blocks, arithmetic, application, etc.

      The compile-time ENVIRONMENT is deliberately separate from the program's
      runtime environment -- a macro body sees only OTHER MACROS plus the
      builtin `Compiler` members.  It does NOT see ordinary top-level
      definitions (compile-time code cannot call runtime code).

      Two `Compiler` builtins are seeded:
        * `Ast`        -- an opaque nominal type (`type_constructor("Ast", [])`),
                          the type of a quasiquote and of `parseItem`'s result.
        * `parseItem`  -- `(string): Ast`, parses one program item from text.
      The quasiquote / unquote typing rules live in `analyser/infer.pl`
      (`quote_node` has type `Ast`; each `~e` must be an `Ast`).  Quoted
      TEMPLATES are not checked here -- they are checked after expansion, at the
      use site (see the docs' "two type-check moments").

    NOTE: expansion (`@name(..)` -> spliced Ast) is not implemented yet; this
    file establishes the type-check stage only.
*/

:- use_module(library(assoc)).
:- use_module(library(lists)).
:- use_module('../analyser', [analyse_module/5]).
:- use_module('../parser', [parse/2]).

%% check_macros(+ProgramAst).
%
% Type-check every macro definition in the program.  Succeeds (with no output)
% when the program defines no macros; otherwise throws `analysis_error(Reason)`
% on the first ill-typed macro body, exactly like ordinary inference.
check_macros(program_node(Items)) :-
  collect_macros(Items, MacroDefinitions),
  collect_compiler_imports(Items, ImportedNames),
  check_macro_set(MacroDefinitions, ImportedNames).

%% check_macro_set(+MacroDefinitions, +CompilerImportNames).
%
% Type-check a set of macro definitions together (so they may reference one
% another).  Used both per-file (`check_macros/1`) and whole-program (the loader
% passes EVERY module's macros, so a macro in one file may call a macro imported
% from another).  Succeeds trivially when there are no macros.
check_macro_set([], _CompilerImportNames) :- !.
check_macro_set(MacroDefinitions, CompilerImportNames) :-
  validate_compiler_imports(CompilerImportNames),
  seed_environments(CompilerImportNames, SeedValueEnvironment, SeedTypeEnvironment),
  desugar_macros(MacroDefinitions, DesugaredDefinitions),
  analyse_module(program_node(DesugaredDefinitions),
                 SeedValueEnvironment, SeedTypeEnvironment, _Result, _Interface).

%% require_parse_item_import(+MacroDefinitions, +CompilerImportNames).
%
% Enforce, PER MODULE, that a module whose macro bodies use `parseItem` imports
% it (`use Compiler:(parseItem)`).  The whole-program type check pools every
% module's imports, so it alone would let one file's import satisfy another's
% use; this closes that gap.  `parseItem` is the compiler builtin (compile-time
% only), so a body mentioning it -- anywhere, even inside a quasiquote, where a
% generated `parseItem` call could never run -- requires the import.
require_parse_item_import(MacroDefinitions, CompilerImportNames) :-
  ( memberchk("parseItem", CompilerImportNames) ->
      true
  ; \+ ( member(macro_definition_node(_, _, Body, _), MacroDefinitions),
         mentions_parse_item(Body) ) ->
      true
  ; throw(analysis_error(parse_item_not_imported))
  ).

mentions_parse_item(identifier_node(Name, _)) :-
  Name == "parseItem", !.
mentions_parse_item(Term) :-
  compound(Term),
  Term =.. [_Functor | Arguments],
  member(Argument, Arguments),
  mentions_parse_item(Argument), !.

% ---------------------------------------------------------------------------
% Cross-file helpers (whole-program macro processing; see module_loader.pl)
% ---------------------------------------------------------------------------

%% program_macros(+ProgramAst, -MacroDefinitions).
program_macros(program_node(Items), MacroDefinitions) :-
  collect_macros(Items, MacroDefinitions).

%% program_compiler_imports(+ProgramAst, -CompilerImportNames).
program_compiler_imports(program_node(Items), Names) :-
  collect_compiler_imports(Items, Names).

%% macro_definition_names(+MacroDefinitions, -Names).
macro_definition_names([], []).
macro_definition_names([macro_definition_node(Name, _, _, _) | Rest], [Name | Names]) :-
  macro_definition_names(Rest, Names).

%% macro_table(+MacroDefinitions, -Table).
%
% Build the name -> definition table used by the interpreter.  Macro names are
% a single global namespace, so a name defined in two files is a `duplicate_macro`
% error.
macro_table(MacroDefinitions, Table) :-
  empty_assoc(Empty),
  insert_unique_macros(MacroDefinitions, Empty, Table).

insert_unique_macros([], Table, Table).
insert_unique_macros([macro_definition_node(Name, Parameters, Body, Span) | Rest], TableIn, TableOut) :-
  ( get_assoc(Name, TableIn, _) ->
      throw(analysis_error(duplicate_macro(Name)))
  ; true
  ),
  put_assoc(Name, TableIn, macro_definition_node(Name, Parameters, Body, Span), Table1),
  insert_unique_macros(Rest, Table1, TableOut).

% ---------------------------------------------------------------------------
% Collecting macro definitions (bare or `public`-wrapped)
% ---------------------------------------------------------------------------

collect_macros([], []).
collect_macros([macro_definition_node(Name, Parameters, Body, Span) | Rest],
               [macro_definition_node(Name, Parameters, Body, Span) | Macros]) :- !,
  collect_macros(Rest, Macros).
collect_macros([public_node(macro_definition_node(Name, Parameters, Body, Span), _) | Rest],
               [macro_definition_node(Name, Parameters, Body, Span) | Macros]) :- !,
  collect_macros(Rest, Macros).
collect_macros([_Other | Rest], Macros) :-
  collect_macros(Rest, Macros).

% ---------------------------------------------------------------------------
% The builtin `Compiler` import:  use Compiler:(Ast parseItem)
% ---------------------------------------------------------------------------

% Gather the names imported from the builtin `Compiler` module across all of its
% `use` declarations (a whole-module `use Compiler` -- `use_all_node` -- is not
% supported: the members must be named).
collect_compiler_imports([], []).
collect_compiler_imports([use_node(Path, Names, _) | Rest], All) :-
  Path == "Compiler", !,
  collect_compiler_imports(Rest, RestNames),
  append(Names, RestNames, All).
collect_compiler_imports([_Other | Rest], All) :-
  collect_compiler_imports(Rest, All).

% Only `Ast` and `parseItem` may be imported from `Compiler`.
validate_compiler_imports([]).
validate_compiler_imports([Name | Names]) :-
  ( Name == "Ast" ; Name == "parseItem" ), !,
  validate_compiler_imports(Names).
validate_compiler_imports([Name | _]) :-
  throw(analysis_error(unknown_compiler_import(Name))).

% ---------------------------------------------------------------------------
% The compile-time seed environments
% ---------------------------------------------------------------------------

% Seed the `Compiler` builtins a macro body may use.  `parseItem` is bound ONLY
% when it is imported (`use Compiler:(parseItem)`), so calling it without the
% import is an `unbound_variable` -- imports are enforced.  The `Ast` TYPE is
% always available (the inferred macro return is `Ast`), so importing `Ast` is
% optional and needed only if you write the name explicitly.  Names are keyed by
% their plain character lists so they compare equal to names the parser produced.
seed_environments(CompilerImportNames, ValueEnvironment, TypeEnvironment) :-
  empty_assoc(EmptyValues),
  ( memberchk("parseItem", CompilerImportNames) ->
      put_assoc("parseItem", EmptyValues,
                defined(type_scheme([], function_type([string], type_constructor("Ast", [])))),
                ValueEnvironment)
  ; ValueEnvironment = EmptyValues
  ),
  empty_assoc(EmptyTypes),
  put_assoc("Ast", EmptyTypes, type_variant_info([], []), TypeEnvironment).

% ---------------------------------------------------------------------------
% Desugaring a macro to a value definition  `NAME = (params): Ast BODY`
% ---------------------------------------------------------------------------

desugar_macros([], []).
desugar_macros([Macro | Macros], [Definition | Definitions]) :-
  desugar_macro(Macro, Definition),
  desugar_macros(Macros, Definitions).

desugar_macro(macro_definition_node(Name, Parameters, Body, Span),
              definition_node(identifier_node(Name, Span),
                              no_annotation,
                              function_node([], ParameterNodes,
                                            type_annotation(type_name_node("Ast", [], Span)),
                                            Body, Span),
                              Span)) :-
  desugar_parameters(Parameters, Span, ParameterNodes).

% Each macro parameter becomes an untyped binding pattern.  (The macro's own
% span stands in for the per-parameter span, which the parser does not retain.)
desugar_parameters([], _Span, []).
desugar_parameters([Name | Names], Span,
                   [parameter_node(binding_pattern(Name, Span), no_annotation, Span) | Rest]) :-
  desugar_parameters(Names, Span, Rest).

% ===========================================================================
% EXPANSION  (expand_macros/2)
% ===========================================================================

/*  Replace every `@name(args) source` invocation with the AST the macro
    produces, then drop the macro definitions and the `Compiler` import.  Run
    AFTER `check_macros/1` (so we never interpret an ill-typed body) and BEFORE
    module expansion (so the rest of the pipeline never sees a macro node).

    An `Ast` VALUE is represented as the parser node term itself, wrapped
    `ast(Node)`.  This makes `parseItem` a call to the parser, a quasiquote a
    structural rebuild (`reify/4`), and splicing trivial -- no separate
    reflection layer.

    Expansion is a FIXPOINT: a macro whose result itself contains `@...`
    invocations is expanded again (a non-terminating macro will loop -- the
    same hazard as any recursive definition).
*/

%% expand_macros(+ProgramIn, -ProgramOut).
expand_macros(program_node(Items), program_node(OutItems)) :-
  build_macro_table(Items, Table),
  exclude_macro_items(Items, Kept),
  expand_each(Kept, Table, OutItems).

build_macro_table(Items, Table) :-
  collect_macros(Items, Macros),
  empty_assoc(Empty),
  insert_macros(Macros, Empty, Table).

insert_macros([], Table, Table).
insert_macros([Definition | Rest], TableIn, TableOut) :-
  Definition = macro_definition_node(Name, _, _, _),
  put_assoc(Name, TableIn, Definition, Table1),
  insert_macros(Rest, Table1, TableOut).

% Drop macro definitions (bare or `public`) and the builtin `Compiler` import;
% everything else is kept (and macro-expanded).
exclude_macro_items([], []).
exclude_macro_items([Item | Rest], Kept) :-
  ( macro_or_compiler_item(Item) -> Kept = Kept1 ; Kept = [Item | Kept1] ),
  exclude_macro_items(Rest, Kept1).

macro_or_compiler_item(macro_definition_node(_, _, _, _)).
macro_or_compiler_item(public_node(macro_definition_node(_, _, _, _), _)).
macro_or_compiler_item(use_node(Path, _, _)) :- Path == "Compiler".

expand_each([], _Table, []).
expand_each([Item | Rest], Table, [Out | Outs]) :-
  expand_term(Item, Table, Out),
  expand_each(Rest, Table, Outs).

% Walk a term: expand a macro invocation (then re-expand its result), otherwise
% recurse structurally.  Atomic terms (and spans) are returned unchanged.
expand_term(macro_call_node(Name, ArgumentExpressions, Source, _Span), Table, Out) :- !,
  expand_invocation(Name, ArgumentExpressions, Source, Table, Node),
  expand_term(Node, Table, Out).
expand_term(Term, Table, Out) :-
  compound(Term), !,
  Term =.. [Functor | Arguments],
  expand_arguments(Arguments, Table, Arguments1),
  Out =.. [Functor | Arguments1].
expand_term(Atomic, _Table, Atomic).

expand_arguments([], _Table, []).
expand_arguments([Argument | Arguments], Table, [Out | Outs]) :-
  expand_term(Argument, Table, Out),
  expand_arguments(Arguments, Table, Outs).

% One `@name(args) source`: evaluate the `( )` arguments, append the raw source
% text as the final parameter, bind the macro's parameters, interpret the body.
expand_invocation(Name, ArgumentExpressions, Source, Table, Node) :-
  ( get_assoc(Name, Table, macro_definition_node(_, Parameters, Body, _)) ->
      true
  ; throw(analysis_error(unknown_macro(Name)))
  ),
  empty_assoc(EmptyEnvironment),
  eval_each(ArgumentExpressions, EmptyEnvironment, Table, ArgumentValues),
  append(ArgumentValues, [str(Source)], AllValues),
  ( same_length(Parameters, AllValues) ->
      true
  ; throw(analysis_error(macro_argument_count(Name)))
  ),
  bind_names(Parameters, AllValues, EmptyEnvironment, CallEnvironment),
  eval(Body, CallEnvironment, Table, Result),
  ( Result = ast(Node) ->
      true
  ; throw(analysis_error(macro_result_not_ast(Name)))
  ).

bind_names([], [], Environment, Environment).
bind_names([Name | Names], [Value | Values], EnvironmentIn, EnvironmentOut) :-
  put_assoc(Name, EnvironmentIn, Value, Environment1),
  bind_names(Names, Values, Environment1, EnvironmentOut).

% ===========================================================================
% COMPILE-TIME INTERPRETER  (eval/4)
% ===========================================================================
/*  Evaluates a macro body to a VALUE.  Values:

      num(Number)  str(Chars)  bool(true|false)  tuple(Key-Value list)
      closure(Parameters, Body, Env)   -- a lambda
      macro_ref(Name)                  -- a macro used as a function (recursion)
      builtin(parse_item)              -- `Compiler.parseItem`
      ast(Node)                        -- an Ast value (a parser node term)

    The environment is an assoc of local bindings; `Table` is the macro table
    (so a body may call other macros, and itself, as functions).  A macro body
    sees ONLY local bindings, other macros, and `parseItem` -- not the program's
    runtime definitions (compile-time code cannot call runtime code).
*/

eval(number_node(N, _), _Environment, _Table, num(N)).
eval(boolean_node(B, _), _Environment, _Table, bool(B)).
eval(string_node(Parts, _), Environment, Table, str(Chars)) :-
  eval_string_parts(Parts, Environment, Table, Chars).
eval(identifier_node(Name, _), Environment, Table, Value) :-
  resolve_name(Name, Environment, Table, Value).
eval(function_node(_TypeParameters, Parameters, _Return, Body, _), Environment, _Table,
     closure(Parameters, Body, Environment)).
eval(function_call_node(Target, Arguments, _), Environment, Table, Value) :-
  eval(Target, Environment, Table, Function),
  eval_each(Arguments, Environment, Table, ArgumentValues),
  apply_function(Function, ArgumentValues, Table, Value).
eval(conditional_node(Condition, Then, Else, _), Environment, Table, Value) :-
  eval(Condition, Environment, Table, bool(Boolean)),
  ( Boolean == true -> eval(Then, Environment, Table, Value)
  ; eval(Else, Environment, Table, Value)
  ).
eval(unary_node(Operator, Operand, _), Environment, Table, Value) :-
  eval(Operand, Environment, Table, OperandValue),
  apply_unary(Operator, OperandValue, Value).
eval(binary_node(Operator, Left, Right, _), Environment, Table, Value) :-
  eval(Left, Environment, Table, LeftValue),
  eval(Right, Environment, Table, RightValue),
  apply_binary(Operator, LeftValue, RightValue, Value).
eval(block_node(Expressions, _), Environment, Table, Value) :-
  eval_block(Expressions, Environment, Table, Value).
eval(match_node(Scrutinee, Arms, _), Environment, Table, Value) :-
  eval(Scrutinee, Environment, Table, ScrutineeValue),
  eval_match(Arms, ScrutineeValue, Environment, Table, Value).
eval(tuple_node(Members, _), Environment, Table, tuple(Fields)) :-
  eval_members(Members, 0, Environment, Table, Fields).
eval(access_node(Target, Accessor, _), Environment, Table, Value) :-
  eval(Target, Environment, Table, tuple(Fields)),
  accessor_field(Accessor, Key),
  ( memberchk(Key - Value, Fields) -> true ; throw(analysis_error(macro_no_field(Key))) ).
eval(definition_node(_, _, ValueExpression, _), Environment, Table, Value) :-
  eval(ValueExpression, Environment, Table, Value).
% A quasiquote evaluates to an `Ast`: rebuild the template, splicing unquotes.
eval(quote_node(Template, _), Environment, Table, ast(Node)) :-
  reify(Template, Environment, Table, Node).
eval(unquote_node(_, _), _Environment, _Table, _Value) :-
  throw(analysis_error(unquote_outside_quasiquote)).

eval_each([], _Environment, _Table, []).
eval_each([Expression | Expressions], Environment, Table, [Value | Values]) :-
  eval(Expression, Environment, Table, Value),
  eval_each(Expressions, Environment, Table, Values).

% Name resolution: a local binding, then `parseItem`, then a macro (as a
% callable function), else an unbound-variable error.
resolve_name(Name, Environment, _Table, Value) :-
  get_assoc(Name, Environment, Value), !.
resolve_name(Name, _Environment, _Table, builtin(parse_item)) :-
  Name == "parseItem", !.
resolve_name(Name, _Environment, Table, macro_ref(Name)) :-
  get_assoc(Name, Table, _), !.
resolve_name(Name, _Environment, _Table, _Value) :-
  throw(analysis_error(macro_unbound_variable(Name))).

% Application.  `parseItem` parses one program item from text into an Ast; a
% macro-as-function binds ALL its parameters to the arguments (this is the
% recursion path); a closure binds its parameter patterns.
apply_function(builtin(parse_item), [str(Chars)], _Table, ast(Node)) :- !,
  parse_item(Chars, Node).
apply_function(macro_ref(Name), ArgumentValues, Table, Value) :- !,
  get_assoc(Name, Table, macro_definition_node(_, Parameters, Body, _)),
  ( same_length(Parameters, ArgumentValues) -> true ; throw(analysis_error(macro_argument_count(Name))) ),
  empty_assoc(Empty),
  bind_names(Parameters, ArgumentValues, Empty, CallEnvironment),
  eval(Body, CallEnvironment, Table, Value).
apply_function(closure(Parameters, Body, CapturedEnvironment), ArgumentValues, Table, Value) :- !,
  bind_parameters(Parameters, ArgumentValues, CapturedEnvironment, CallEnvironment),
  eval(Body, CallEnvironment, Table, Value).
apply_function(Other, _ArgumentValues, _Table, _Value) :-
  throw(analysis_error(macro_not_callable(Other))).

bind_parameters([], [], Environment, Environment).
bind_parameters([parameter_node(Pattern, _, _) | Parameters], [Value | Values], EnvironmentIn, EnvironmentOut) :-
  match_pattern(Pattern, Value, EnvironmentIn, _Table, Environment1),
  bind_parameters(Parameters, Values, Environment1, EnvironmentOut).

% `parseItem`: parse the text as a program and require exactly one item.
parse_item(Chars, Node) :-
  ( parse(Chars, program_node(Items)) -> true ; throw(analysis_error(macro_parse_failed(Chars))) ),
  ( Items = [Node] -> true ; throw(analysis_error(macro_parse_not_single_item(Chars))) ).

% A block: definitions bind sequentially; the block's value is its last
% expression (a trailing definition yields its bound value).
eval_block([Expression], Environment, Table, Value) :- !,
  eval(Expression, Environment, Table, Value).
eval_block([Expression | Rest], Environment, Table, Value) :-
  ( Expression = definition_node(identifier_node(Name, _), _, ValueExpression, _) ->
      eval(ValueExpression, Environment, Table, BoundValue),
      put_assoc(Name, Environment, BoundValue, Environment1)
  ; eval(Expression, Environment, Table, _Discarded),
    Environment1 = Environment
  ),
  eval_block(Rest, Environment1, Table, Value).
eval_block([], _Environment, _Table, tuple([])).

% Match: first arm whose (or-)pattern matches and whose guard holds.
eval_match([match_arm(Patterns, Guard, Result, _) | Rest], ScrutineeValue, Environment, Table, Value) :-
  ( match_any(Patterns, ScrutineeValue, Environment, Table, ArmEnvironment),
    guard_true(Guard, ArmEnvironment, Table)
  ->
    eval(Result, ArmEnvironment, Table, Value)
  ; eval_match(Rest, ScrutineeValue, Environment, Table, Value)
  ).
eval_match([], _ScrutineeValue, _Environment, _Table, _Value) :-
  throw(analysis_error(macro_non_exhaustive_match)).

match_any([Pattern | _], Value, Environment, Table, ArmEnvironment) :-
  match_pattern(Pattern, Value, Environment, Table, ArmEnvironment), !.
match_any([_ | Rest], Value, Environment, Table, ArmEnvironment) :-
  match_any(Rest, Value, Environment, Table, ArmEnvironment).

guard_true(no_guard, _Environment, _Table).
guard_true(guard(Expression), Environment, Table) :-
  eval(Expression, Environment, Table, bool(true)).

match_pattern(wildcard_pattern(_), _Value, Environment, _Table, Environment).
match_pattern(binding_pattern(Name, _), Value, EnvironmentIn, _Table, EnvironmentOut) :-
  put_assoc(Name, EnvironmentIn, Value, EnvironmentOut).
match_pattern(literal_pattern(Node, _), Value, Environment, Table, Environment) :-
  eval(Node, Environment, Table, LiteralValue),
  values_equal(LiteralValue, Value).
match_pattern(record_pattern(Members, _), tuple(Fields), Environment, Table, EnvironmentOut) :-
  match_record(Members, 0, Fields, Environment, Table, EnvironmentOut).

match_record([], _Index, _Fields, Environment, _Table, Environment).
match_record([positional_member_pattern(Pattern, _) | Rest], Index, Fields, EnvironmentIn, Table, EnvironmentOut) :-
  memberchk(index(Index) - Value, Fields),
  match_pattern(Pattern, Value, EnvironmentIn, Table, Environment1),
  Index1 is Index + 1,
  match_record(Rest, Index1, Fields, Environment1, Table, EnvironmentOut).
match_record([labeled_member_pattern(Name, Pattern, _) | Rest], Index, Fields, EnvironmentIn, Table, EnvironmentOut) :-
  memberchk(label(Name) - Value, Fields),
  match_pattern(Pattern, Value, EnvironmentIn, Table, Environment1),
  match_record(Rest, Index, Fields, Environment1, Table, EnvironmentOut).

values_equal(num(A), num(B)) :- A =:= B.
values_equal(bool(B), bool(B)).
values_equal(str(A), str(B)) :- A == B.

% Tuple members -> a field list keyed by `index(I)` / `label(Name)`.
eval_members([], _Index, _Environment, _Table, []).
eval_members([tuple_member(_Mutability, positional, _Annotation, ValueExpression, _) | Rest], Index, Environment, Table,
             [index(Index) - Value | Fields]) :-
  eval(ValueExpression, Environment, Table, Value),
  Index1 is Index + 1,
  eval_members(Rest, Index1, Environment, Table, Fields).
eval_members([tuple_member(_Mutability, labeled(Name), _Annotation, ValueExpression, _) | Rest], Index, Environment, Table,
             [label(Name) - Value | Fields]) :-
  eval(ValueExpression, Environment, Table, Value),
  eval_members(Rest, Index, Environment, Table, Fields).

accessor_field(label(Name, _), label(Name)).
accessor_field(index(Index, _), index(Index)).

eval_string_parts([], _Environment, _Table, []).
eval_string_parts([string_static_part(Chars) | Rest], Environment, Table, All) :-
  eval_string_parts(Rest, Environment, Table, RestChars),
  append(Chars, RestChars, All).
eval_string_parts([string_interpolated_part(Node) | Rest], Environment, Table, All) :-
  eval(Node, Environment, Table, Value),
  value_to_chars(Value, Chars),
  eval_string_parts(Rest, Environment, Table, RestChars),
  append(Chars, RestChars, All).

value_to_chars(str(Chars), Chars).
value_to_chars(num(N), Chars) :- number_chars(N, Chars).

apply_unary(number_negation, num(N), num(M)) :- M is -N.
apply_unary(bit_invertion, num(N), num(M)) :- M is \ N.
apply_unary(boolean_negation, bool(B), bool(R)) :- negate(B, R).

negate(true, false).
negate(false, true).

apply_binary(addition, num(A), num(B), num(C)) :- C is A + B.
apply_binary(subtraction, num(A), num(B), num(C)) :- C is A - B.
apply_binary(multiplication, num(A), num(B), num(C)) :- C is A * B.
apply_binary(division, num(A), num(B), num(C)) :- C is A / B.
apply_binary(less_than, num(A), num(B), bool(R)) :- ( A < B -> R = true ; R = false ).
apply_binary(less_than_or_equal, num(A), num(B), bool(R)) :- ( A =< B -> R = true ; R = false ).
apply_binary(greater_than, num(A), num(B), bool(R)) :- ( A > B -> R = true ; R = false ).
apply_binary(greater_than_or_equal, num(A), num(B), bool(R)) :- ( A >= B -> R = true ; R = false ).
apply_binary(equal, A, B, bool(R)) :- ( values_equal(A, B) -> R = true ; R = false ).
apply_binary(not_equal, A, B, bool(R)) :- ( values_equal(A, B) -> R = false ; R = true ).
apply_binary(and, bool(A), bool(B), bool(R)) :- ( A == true, B == true -> R = true ; R = false ).
apply_binary(or, bool(A), bool(B), bool(R)) :- ( ( A == true ; B == true ) -> R = true ; R = false ).
apply_binary(Operator, _Left, _Right, _Value) :-
  \+ member(Operator, [addition, subtraction, multiplication, division,
                       less_than, less_than_or_equal, greater_than, greater_than_or_equal,
                       equal, not_equal, and, or]),
  throw(analysis_error(macro_unsupported_operator(Operator))).

% Rebuild a quasiquote template into an Ast node, splicing each `~e` with the
% Ast value `e` evaluates to.  Everything else is reconstructed verbatim.
reify(unquote_node(Expression, _), Environment, Table, Node) :- !,
  eval(Expression, Environment, Table, Value),
  ( Value = ast(Node) -> true ; throw(analysis_error(macro_unquote_not_ast(Value))) ).
reify(Term, Environment, Table, Node) :-
  compound(Term), !,
  Term =.. [Functor | Arguments],
  reify_each(Arguments, Environment, Table, Arguments1),
  Node =.. [Functor | Arguments1].
reify(Atomic, _Environment, _Table, Atomic).

reify_each([], _Environment, _Table, []).
reify_each([Argument | Arguments], Environment, Table, [Node | Nodes]) :-
  reify(Argument, Environment, Table, Node),
  reify_each(Arguments, Environment, Table, Nodes).

% ===========================================================================
% MODULE-QUALIFIED RESOLUTION  (cross-file macros)
% ===========================================================================
/*  Macro names are MODULE-SCOPED, so two files may reuse a name.  Each macro is
    given a globally-unique KEY (`Name#ModuleIndex`).  A per-module RESOLUTION
    map sends each name as written in that module (a bare `times`, or a dotted
    `macros.times` from a whole-module import) to the key of the macro it
    denotes.  The loader (`module_loader.pl`) builds these maps from imports;
    here we apply them:

      * `resolve_macro_body/3` rewrites a macro BODY -- every macro reference
        becomes its key -- so the global key-keyed table and the interpreter
        need no per-module context.  It is SCOPE-AWARE (a lambda/block/match
        binding shadows a macro name) and QUASIQUOTE-AWARE (a quoted template is
        left verbatim; only its unquotes -- which are code -- are rewritten).

      * `resolve_uses/3` rewrites a module's ordinary code: only `@name(..)`
        invocation names (and nested ones in arguments) become keys; bare
        identifiers are left alone (in runtime code a bare name is a value, not
        a macro).  An unresolved `@name` is an error (the macro is not in scope).
*/

%% macro_key_name(+ModuleIndex, +Name, -KeyChars).
%
% A unique internal name for a macro: `Name#Index`.  `#` cannot occur in a
% source identifier, so a key never collides with a user name; the key is only
% an assoc/identifier key during macro processing and never reaches codegen.
macro_key_name(ModuleIndex, Name, KeyChars) :-
  number_chars(ModuleIndex, Digits),
  append(Name, ['#' | Digits], Raw),
  % Rebuild as fresh cons cells so the key has ONE representation: `library(assoc)`
  % orders keys with `compare/3`, which treats a partial string and an equal cons
  % list as different, so a mixed-provenance key would be silently unfindable.
  canonical_chars(Raw, KeyChars).

canonical_chars([], []).
canonical_chars([Character | Characters], [Character | Rest]) :-
  canonical_chars(Characters, Rest).

%% resolve_macro_body(+Body, +Resolution, -ResolvedBody).
resolve_macro_body(Body, Resolution, ResolvedBody) :-
  resolve_references(Body, Resolution, [], ResolvedBody).

% `Locals` are names bound by enclosing lambda parameters / block definitions /
% match patterns; such a name shadows any macro of the same name.
resolve_references(identifier_node(Name, Span), Resolution, Locals, Out) :- !,
  ( memberchk(Name, Locals) ->
      Out = identifier_node(Name, Span)
  ; get_assoc(Name, Resolution, Key) ->
      Out = identifier_node(Key, Span)
  ; Out = identifier_node(Name, Span)
  ).
resolve_references(macro_call_node(Name, Arguments, Source, Span), Resolution, Locals, Out) :- !,
  ( get_assoc(Name, Resolution, Key) -> true ; Key = Name ),
  resolve_references_list(Arguments, Resolution, Locals, Arguments1),
  Out = macro_call_node(Key, Arguments1, Source, Span).
resolve_references(function_node(TypeParameters, Parameters, Return, Body, Span), Resolution, Locals, Out) :- !,
  parameters_variables(Parameters, ParameterVariables),
  append(ParameterVariables, Locals, Locals1),
  resolve_references(Body, Resolution, Locals1, Body1),
  Out = function_node(TypeParameters, Parameters, Return, Body1, Span).
resolve_references(block_node(Expressions, Span), Resolution, Locals, Out) :- !,
  block_definition_names(Expressions, DefinitionNames),
  append(DefinitionNames, Locals, Locals1),
  resolve_references_list(Expressions, Resolution, Locals1, Expressions1),
  Out = block_node(Expressions1, Span).
resolve_references(match_node(Scrutinee, Arms, Span), Resolution, Locals, Out) :- !,
  resolve_references(Scrutinee, Resolution, Locals, Scrutinee1),
  resolve_match_arms(Arms, Resolution, Locals, Arms1),
  Out = match_node(Scrutinee1, Arms1, Span).
resolve_references(quote_node(Template, Span), Resolution, Locals, Out) :- !,
  resolve_quote(Template, Resolution, Locals, Template1),
  Out = quote_node(Template1, Span).
resolve_references(unquote_node(Inner, Span), Resolution, Locals, Out) :- !,
  resolve_references(Inner, Resolution, Locals, Inner1),
  Out = unquote_node(Inner1, Span).
resolve_references(definition_node(Identifier, Annotation, Value, Span), Resolution, Locals, Out) :- !,
  resolve_references(Value, Resolution, Locals, Value1),
  Out = definition_node(Identifier, Annotation, Value1, Span).
resolve_references(Term, Resolution, Locals, Out) :-
  compound(Term), !,
  Term =.. [Functor | Arguments],
  resolve_references_list(Arguments, Resolution, Locals, Arguments1),
  Out =.. [Functor | Arguments1].
resolve_references(Atomic, _Resolution, _Locals, Atomic).

resolve_references_list([], _Resolution, _Locals, []).
resolve_references_list([Term | Terms], Resolution, Locals, [Out | Outs]) :-
  resolve_references(Term, Resolution, Locals, Out),
  resolve_references_list(Terms, Resolution, Locals, Outs).

% Inside a quasiquote only the unquotes are code; the template is verbatim.
resolve_quote(unquote_node(Inner, Span), Resolution, Locals, unquote_node(Inner1, Span)) :- !,
  resolve_references(Inner, Resolution, Locals, Inner1).
resolve_quote(Term, Resolution, Locals, Out) :-
  compound(Term), !,
  Term =.. [Functor | Arguments],
  resolve_quote_list(Arguments, Resolution, Locals, Arguments1),
  Out =.. [Functor | Arguments1].
resolve_quote(Atomic, _Resolution, _Locals, Atomic).

resolve_quote_list([], _Resolution, _Locals, []).
resolve_quote_list([Term | Terms], Resolution, Locals, [Out | Outs]) :-
  resolve_quote(Term, Resolution, Locals, Out),
  resolve_quote_list(Terms, Resolution, Locals, Outs).

resolve_match_arms([], _Resolution, _Locals, []).
resolve_match_arms([match_arm(Patterns, Guard, Result, Span) | Rest], Resolution, Locals,
                   [match_arm(Patterns, Guard1, Result1, Span) | Rest1]) :-
  patterns_variables(Patterns, PatternVariables),
  append(PatternVariables, Locals, Locals1),
  resolve_guard(Guard, Resolution, Locals1, Guard1),
  resolve_references(Result, Resolution, Locals1, Result1),
  resolve_match_arms(Rest, Resolution, Locals, Rest1).

resolve_guard(no_guard, _Resolution, _Locals, no_guard).
resolve_guard(guard(Expression), Resolution, Locals, guard(Expression1)) :-
  resolve_references(Expression, Resolution, Locals, Expression1).

%% resolve_uses(+Term, +Resolution, -Out).
%
% Rewrite only `@name(..)` invocation names (recursing into arguments) to keys;
% leave ordinary identifiers untouched.  An `@name` not in `Resolution` is a
% macro that is neither defined locally nor imported -- an error.
resolve_uses(macro_call_node(Name, Arguments, Source, Span), Resolution, Out) :- !,
  ( get_assoc(Name, Resolution, Key) ->
      true
  ; throw(analysis_error(unknown_macro(Name)))
  ),
  resolve_uses_list(Arguments, Resolution, Arguments1),
  Out = macro_call_node(Key, Arguments1, Source, Span).
resolve_uses(Term, Resolution, Out) :-
  compound(Term), !,
  Term =.. [Functor | Arguments],
  resolve_uses_list(Arguments, Resolution, Arguments1),
  Out =.. [Functor | Arguments1].
resolve_uses(Atomic, _Resolution, Atomic).

resolve_uses_list([], _Resolution, []).
resolve_uses_list([Term | Terms], Resolution, [Out | Outs]) :-
  resolve_uses(Term, Resolution, Out),
  resolve_uses_list(Terms, Resolution, Outs).

%% expand_program_with_table(+ProgramAst, +Table, -ExpandedAst).
%
% Interpret every `@key(..)` invocation in an already-resolved, already-stripped
% program, using a pre-built key-keyed `Table`.
expand_program_with_table(program_node(Items), Table, program_node(OutItems)) :-
  expand_each(Items, Table, OutItems).

% Variables bound by a list of parameters / patterns (for shadow tracking).
parameters_variables([], []).
parameters_variables([parameter_node(Pattern, _Annotation, _Span) | Rest], Variables) :-
  pattern_variables(Pattern, PatternVariables),
  parameters_variables(Rest, RestVariables),
  append(PatternVariables, RestVariables, Variables).

patterns_variables([], []).
patterns_variables([Pattern | Patterns], Variables) :-
  pattern_variables(Pattern, Head),
  patterns_variables(Patterns, Tail),
  append(Head, Tail, Variables).

pattern_variables(wildcard_pattern(_), []).
pattern_variables(binding_pattern(Name, _), [Name]).
pattern_variables(literal_pattern(_, _), []).
pattern_variables(constructor_pattern(_Name, SubPatterns, _), Variables) :-
  patterns_variables(SubPatterns, Variables).
pattern_variables(record_pattern(Members, _), Variables) :-
  member_pattern_variables(Members, Variables).

member_pattern_variables([], []).
member_pattern_variables([Member | Members], Variables) :-
  ( Member = positional_member_pattern(SubPattern, _)
  ; Member = labeled_member_pattern(_Label, SubPattern, _)
  ),
  pattern_variables(SubPattern, Head),
  member_pattern_variables(Members, Tail),
  append(Head, Tail, Variables).

block_definition_names([], []).
block_definition_names([definition_node(identifier_node(Name, _), _, _, _) | Rest], [Name | Names]) :- !,
  block_definition_names(Rest, Names).
block_definition_names([destructuring_node(Pattern, _, _) | Rest], Names) :- !,
  pattern_variables(Pattern, PatternVariables),
  block_definition_names(Rest, RestNames),
  append(PatternVariables, RestNames, Names).
block_definition_names([_Other | Rest], Names) :-
  block_definition_names(Rest, Names).
