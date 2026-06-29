:- module(lower, [lower/2, parse_source/2]).

/*  source/syntax/lower.pl  --  Green tree  ->  existing `*_node` AST.
    ========================================================================

    The recovering parser (`parser.pl`) produces a LOSSLESS GREEN TREE
    (`node(Kind,Children)` with trivia/punctuation leaves kept).  The batch
    analyser and generator consume the historical AST of spanned `*_node`
    terms (`definition_node/4`, `binary_node/4`, ...).  `lower/2` bridges them:
    it drops trivia/punctuation, recovers numeric values and string parts, and
    rebuilds the exact node shapes the back-end expects.

    SPANS.  Green leaves carry the same 0-based char offsets the old parser
    used, so a node's span is just (start of its first significant leaf .. end
    of its last) -- `gspan/2`.  Trivia / `missing` leaves are excluded, so a
    span brackets only real source, matching the old convention.

    STRUCTURE.  For each green node Kind we know the child layout, so lowering
    pulls out the sub-NODES (`child_nodes/2`) and the few meaningful tokens
    (operator, accessor name, ...) and ignores the structural punctuation.

    COVERAGE.  Programs, definitions / assignments / destructuring, all
    expression forms (literals incl. interpolated strings, binary/unary,
    call/access, if, match + patterns, block, tuple/record, function literal,
    placeholder), reader macros (def/call/quote/unquote), and the item forms
    use / external / type / module.  Type expressions are lowered for
    annotations.  Anything unrecognised lowers to `error_node(Span)` rather
    than failing, so a partial/broken tree still lowers.
*/

:- set_prolog_flag(double_quotes, chars).

:- use_module(library(lists)).
:- use_module('../parser/number_literal', [number_literal//1]).
:- use_module('../parser/position', [set_input_length/1]).
:- use_module('lexer',  [tokenize/2]).
:- use_module('parser', [parse_tokens/3]).

% ===========================================================================
% Leaves, spans, child extraction.
% ===========================================================================

leaves(t(K, Tx, S, E), [t(K, Tx, S, E)]) :- !.
leaves(node(_, Children), Leaves) :- leaves_list(Children, Leaves).

leaves_list([], []).
leaves_list([C | Cs], Leaves) :-
  leaves(C, L1), leaves_list(Cs, L2), append(L1, L2, Leaves).

trivia_leaf(t(whitespace, _, _, _)).
trivia_leaf(t(comment, _, _, _)).
trivia_leaf(t(missing, _, _, _)).

% Scryer's library(lists) has no exclude/3.
my_exclude(_Pred, [], []).
my_exclude(Pred, [X | Xs], Ys) :-
  ( call(Pred, X) -> Ys = Ys1 ; Ys = [X | Ys1] ),
  my_exclude(Pred, Xs, Ys1).

% gspan(+Green, -span(Start,End)): span over the node's significant leaves.
gspan(Green, span(Start, End)) :-
  leaves(Green, All),
  my_exclude(trivia_leaf, All, Sig),
  ( Sig = [t(_, _, Start, _) | _], append(_, [t(_, _, _, End)], Sig) -> true
  ; Start = 0, End = 0 ).

% The sub-NODES of a node's child list (skips all leaf tokens).
child_nodes([], []).
child_nodes([node(K, C) | Cs], [node(K, C) | Ns]) :- !, child_nodes(Cs, Ns).
child_nodes([_Leaf | Cs], Ns) :- child_nodes(Cs, Ns).

% The first significant token of a given kind among a child list.
child_token([t(K, Tx, S, E) | _], K, t(K, Tx, S, E)) :- !.
child_token([_ | Cs], K, Tok) :- child_token(Cs, K, Tok).

% For a keyword-led item (use/external/type/module/macro) the leading ident IS
% the keyword, so the declared name is the SECOND direct-child identifier.
item_name(Ch, Name) :-
  findall(N, member(t(ident, N, _, _), Ch), [_Keyword, Name | _]).

% Direct-child identifier tokens after the first `(` (import names / macro params).
names_in_parens(Ch, Names) :-
  ( append(_, [t('(', _, _, _) | After], Ch) ->
      findall(N, member(t(ident, N, _, _), After), Names)
  ; Names = [] ).

% ===========================================================================
% Program and items.
% ===========================================================================

lower(node(program, Children), program_node(Items)) :-
  child_nodes(Children, ItemNodes),
  maplist_lower_item(ItemNodes, Items).

%% parse_source(+Chars, -Ast): the whole new front-end as a drop-in replacement
%% for the old `parser:parse/2` -- tokenize, recover-parse, lower.  (Diagnostics
%% are discarded here; the LSP path keeps them.)
parse_source(Chars, Ast) :-
  tokenize(Chars, Tokens),
  parse_tokens(Tokens, Green, _Diagnostics),
  lower(Green, Ast).

maplist_lower_item([], []).
maplist_lower_item([N | Ns], [A | As]) :- lower_item(N, A), maplist_lower_item(Ns, As).

lower_item(node(use, Ch), Node)              :- !, lower_use(node(use, Ch), Node).
lower_item(node(public, Ch), public_node(Inner, Span)) :- !,
  child_nodes(Ch, [InnerNode]), lower_item(InnerNode, Inner), gspan(node(public, Ch), Span).
lower_item(node(external, Ch), Node)         :- !, lower_external(node(external, Ch), Node).
lower_item(node(type_declaration, Ch), Node) :- !, lower_type_declaration(node(type_declaration, Ch), Node).
lower_item(node(module, Ch), module_node(Name, Items, Span)) :- !,
  item_name(Ch, Name),
  module_body_nodes(Ch, BodyNodes),
  maplist_lower_item(BodyNodes, Items),
  gspan(node(module, Ch), Span).
lower_item(node(macro_definition, Ch), macro_definition_node(Name, Params, Body, Span)) :- !,
  item_name(Ch, Name),
  names_in_parens(Ch, Params),
  child_nodes(Ch, BodyNodes), append(_, [BodyGreen], BodyNodes),   % body is the last sub-node
  lower_expr(BodyGreen, Body),
  gspan(node(macro_definition, Ch), Span).
lower_item(node(definition, Ch), Node) :- !, lower_definition(node(definition, Ch), Node).
lower_item(Green, Node) :- lower_expr(Green, Node).      % a bare-expression item

% A module body's item nodes are every sub-node after the module name; the name
% identifier is a leaf, so child_nodes already gives exactly the body items.
module_body_nodes(Ch, BodyNodes) :- child_nodes(Ch, BodyNodes).

% ---------------------------------------------------------------------------
% Definitions:  LHS = RHS  ->  definition / assignment / destructuring.
% ---------------------------------------------------------------------------
lower_definition(node(definition, Ch), Node) :-
  child_nodes(Ch, [LhsGreen, RhsGreen]),
  lower_expr(RhsGreen, Rhs),
  gspan(node(definition, Ch), Span),
  ( LhsGreen = node(identifier, _) ->
      lower_expr(LhsGreen, IdNode),
      Node = definition_node(IdNode, no_annotation, Rhs, Span)
  ; LhsGreen = node(access, _) ->
      lower_expr(LhsGreen, AccessNode),
      Node = assignment_node(AccessNode, Rhs, Span)
  ; LhsGreen = node(group, _) ->
      lower_pattern(LhsGreen, Pattern),
      Node = destructuring_node(Pattern, Rhs, Span)
  ; lower_expr(LhsGreen, IdNode),              % fallback
      Node = definition_node(IdNode, no_annotation, Rhs, Span)
  ).

% ---------------------------------------------------------------------------
% Imports.
% ---------------------------------------------------------------------------
lower_use(node(use, Ch), Node) :-
  use_path_chars(Ch, Path),
  gspan(node(use, Ch), Span),
  ( child_token(Ch, '(', _) ->
      names_in_parens(Ch, Names),
      Node = use_node(Path, Names, Span)
  ; Node = use_all_node(Path, Span) ).

% The path is the contiguous run of token texts after the `use` keyword, up to
% the first `:` / whitespace.  We locate the `use` token (it may be preceded by
% leading trivia when this is not the first item) and take the run after it.
use_path_chars(Ch, Path) :-
  append(_LeadingTrivia, [t(ident, "use", _, _) | AfterUse], Ch), !,
  path_run(AfterUse, PathToks),
  collect_text(PathToks, Path).

path_run([t(K, Tx, S, E) | Ts], [t(K, Tx, S, E) | Rest]) :-
  \+ trivia_leaf(t(K, Tx, S, E)), K \== (:), K \== ('('), !,
  path_run(Ts, Rest).
path_run([t(whitespace, _, _, _) | Ts], Rest) :- !, skip_to_path(Ts, Rest).
path_run(_, []).
skip_to_path(Ts, Rest) :- path_run(Ts, Rest).

collect_text([], []).
collect_text([t(_, Tx, _, _) | Ts], All) :- collect_text(Ts, R), append(Tx, R, All).

% ===========================================================================
% Expressions.
% ===========================================================================

lower_expr(node(number, Ch), number_node(Value, Span)) :- !,
  child_token(Ch, number, t(number, Text, _, _)),
  number_value(Text, Value),
  gspan(node(number, Ch), Span).
lower_expr(node(string, Ch), string_node(Parts, Span)) :- !,
  child_token(Ch, string, t(string, Text, _, _)),
  string_parts(Text, Parts),
  gspan(node(string, Ch), Span).
lower_expr(node(identifier, Ch), Node) :- !,
  child_token(Ch, ident, t(ident, Name, _, _)),
  gspan(node(identifier, Ch), Span),
  ( Name == [t,r,u,e]  -> Node = boolean_node(true, Span)
  ; Name == [f,a,l,s,e] -> Node = boolean_node(false, Span)
  ; Node = identifier_node(Name, Span) ).
lower_expr(node(placeholder, Ch), placeholder_node(Span)) :- !, gspan(node(placeholder, Ch), Span).
lower_expr(node(unary, Ch), unary_node(Op, Operand, Span)) :- !,
  unary_op_token(Ch, Op),
  child_nodes(Ch, [OperandGreen]),
  lower_expr(OperandGreen, Operand),
  gspan(node(unary, Ch), Span).
lower_expr(node(binary, Ch), binary_node(Op, Left, Right, Span)) :- !,
  child_nodes(Ch, [LeftGreen, RightGreen]),
  binary_op_token(Ch, Op),
  lower_expr(LeftGreen, Left), lower_expr(RightGreen, Right),
  gspan(node(binary, Ch), Span).
lower_expr(node(access, Ch), access_node(Target, Accessor, Span)) :- !,
  child_nodes(Ch, [TargetGreen]),
  lower_expr(TargetGreen, Target),
  child_token(Ch, ident, t(ident, Name, NS, NE)),
  Accessor = label(Name, span(NS, NE)),
  gspan(node(access, Ch), Span).
lower_expr(node(call, Ch), function_call_node(Target, Args, Span)) :- !,
  child_nodes(Ch, [TargetGreen | ArgGreens]),
  lower_expr(TargetGreen, Target),
  maplist_lower_expr(ArgGreens, Args),
  gspan(node(call, Ch), Span).
lower_expr(node(group, Ch), Node) :- !, lower_group(node(group, Ch), Node).
lower_expr(node(paren, Ch), Node) :- !,          % single parenthesised expr
  child_nodes(Ch, [Inner]), lower_expr(Inner, Node).
lower_expr(node(block, Ch), block_node(Exprs, Span)) :- !,
  child_nodes(Ch, ExprGreens),
  maplist_lower_item(ExprGreens, Exprs),          % block items may be definitions
  gspan(node(block, Ch), Span).
lower_expr(node(conditional, Ch), conditional_node(Cond, Then, Else, Span)) :- !,
  child_nodes(Ch, [CondG, ThenG, ElseG]),
  lower_expr(CondG, Cond), lower_expr(ThenG, Then), lower_expr(ElseG, Else),
  gspan(node(conditional, Ch), Span).
lower_expr(node(match, Ch), match_node(Scrutinee, Arms, Span)) :- !,
  child_nodes(Ch, [ScrutG | ArmGs]),
  lower_expr(ScrutG, Scrutinee),
  maplist_lower_arm(ArmGs, Arms),
  gspan(node(match, Ch), Span).
lower_expr(node(function, Ch), Node) :- !, lower_function(node(function, Ch), Node).
lower_expr(node(macro_call, Ch), macro_call_node(Name, Args, Source, Span)) :- !,
  macro_call_name(Ch, Name),
  macro_call_args(Ch, ArgGreens), maplist_lower_expr(ArgGreens, Args),
  macro_call_following(Ch, Source),
  gspan(node(macro_call, Ch), Span).
lower_expr(node(quote, Ch), quote_node(Inner, Span)) :- !,
  child_nodes(Ch, [InnerG]), lower_expr(InnerG, Inner), gspan(node(quote, Ch), Span).
lower_expr(node(unquote, Ch), unquote_node(Inner, Span)) :- !,
  child_nodes(Ch, [InnerG]), lower_expr(InnerG, Inner), gspan(node(unquote, Ch), Span).
lower_expr(node(definition, Ch), Node) :- !, lower_definition(node(definition, Ch), Node).
lower_expr(Green, error_node(Span)) :- gspan(Green, Span).   % unrecognised / error node

maplist_lower_expr([], []).
maplist_lower_expr([G | Gs], [A | As]) :- lower_expr(G, A), maplist_lower_expr(Gs, As).

% --- operators: token kind -> AST operator name -------------------------------
unary_op_token(Ch, Op) :- ( child_token(Ch, '!', _) -> Op = boolean_negation
                          ; child_token(Ch, '-', _) -> Op = number_negation
                          ; Op = bit_invertion ).

binary_op_token(Ch, Op) :-
  member(t(K, _, _, _), Ch), binary_name(K, Op), !.

binary_name('*', multiplication). binary_name('/', division).
binary_name('+', addition).       binary_name('-', subtraction).
binary_name('<<', left_bit_shift). binary_name('>>', right_bit_shift).
binary_name('&&', bitwise_and).   binary_name('^^', bitwise_xor). binary_name('||', bitwise_or).
binary_name('<=', less_than_or_equal). binary_name('<', less_than).
binary_name('>=', greater_than_or_equal). binary_name('>', greater_than).
binary_name('==', equal).         binary_name('!=', not_equal).
binary_name('&', and).            binary_name('^', xor). binary_name('|', or).
binary_name('->', pipe).

% ===========================================================================
% Tuples / records (the `group` node), and destructuring patterns from a group.
% ===========================================================================

lower_group(node(group, Ch), tuple_node(Members, Span)) :-
  child_nodes(Ch, MemberGreens),
  maplist_lower_member(MemberGreens, Members),
  gspan(node(group, Ch), Span).

maplist_lower_member([], []).
maplist_lower_member([G | Gs], [M | Ms]) :- lower_member(G, M), maplist_lower_member(Gs, Ms).

% A member node:  [ (mutable|readonly)? EXPR (: TYPE)? ].  EXPR is either a bare
% value (positional) or a `definition` node `name = value` (labeled).
lower_member(node(member, Ch), tuple_member(Mut, Kind, Annotation, Value, Span)) :-
  ( child_token(Ch, ident, t(ident, [m,u,t,a,b,l,e], _, _)) -> Mut = mutable ; Mut = readonly ),
  member_annotation(Ch, Annotation),
  child_nodes(Ch, ValueGreens0),
  exclude_type_node(ValueGreens0, [ValueGreen]),
  ( ValueGreen = node(definition, DCh) ->
      child_nodes(DCh, [NameG, ValG]),
      NameG = node(identifier, NCh), child_token(NCh, ident, t(ident, Label, _, _)),
      Kind = labeled(Label),
      lower_expr(ValG, Value)
  ; Kind = positional, lower_expr(ValueGreen, Value) ),
  gspan(node(member, Ch), Span).

member_annotation(Ch, type_annotation(Type)) :-
  child_token(Ch, ':', _), !,
  child_nodes(Ch, Nodes), append(_, [TypeGreen], Nodes), is_type_node(TypeGreen),
  lower_type(TypeGreen, Type).
member_annotation(_Ch, no_annotation).

is_type_node(node(type_name, _)).
is_type_node(node(type_tuple, _)).
is_type_node(node(function_type, _)).
is_type_node(node(quantified_type, _)).
exclude_type_node(Nodes, Kept) :- my_exclude(is_type_node, Nodes, Kept).

% A group in LHS position is a destructuring record pattern.
lower_pattern(node(group, Ch), record_pattern(Members, Span)) :- !,
  child_nodes(Ch, MemberGreens),
  maplist_lower_pat_member(MemberGreens, Members),
  gspan(node(group, Ch), Span).
lower_pattern(Green, Pat) :- lower_match_pattern(Green, Pat).

maplist_lower_pat_member([], []).
maplist_lower_pat_member([G | Gs], [M | Ms]) :- lower_pat_member(G, M), maplist_lower_pat_member(Gs, Ms).

lower_pat_member(node(member, Ch), positional_member_pattern(Pat, Span)) :-
  child_nodes(Ch, [ValueGreen]),
  green_to_binding(ValueGreen, Pat),
  gspan(node(member, Ch), Span).

green_to_binding(node(identifier, Ch), binding_pattern(Name, Span)) :-
  child_token(Ch, ident, t(ident, Name, _, _)), gspan(node(identifier, Ch), Span).

% ===========================================================================
% Functions.   ( params ) : returntype  body
% ===========================================================================
lower_function(node(function, Ch), function_node(TypeParameters, Params, ReturnAnnotation, Body, Span)) :-
  child_nodes(Ch, Nodes0),
  % A leading `<...>` (generics) lowers to the function's type parameters.
  ( Nodes0 = [node(type_params, PCh) | Nodes] ->
      lower_type_params(node(type_params, PCh), TypeParameters)
  ; Nodes = Nodes0, TypeParameters = [] ),
  % Nodes = [ param-members... , ReturnType, Body ].  The members come from the
  % parameter `( ... )`; then the return type node, then the body expression.
  partition_function(Nodes, ParamMembers, ReturnType, BodyGreen),
  maplist_lower_param(ParamMembers, Params),
  ReturnAnnotation = type_annotation(ReturnTypeAst), lower_type(ReturnType, ReturnTypeAst),
  lower_expr(BodyGreen, Body),
  gspan(node(function, Ch), Span).

% The function node's children (sub-nodes) are the parameter members, then the
% return-type node, then the body.  Parameter members are `member` nodes; the
% return type is a type node; the body is whatever follows.
partition_function(Nodes, ParamMembers, ReturnType, Body) :-
  append(ParamMembers, [ReturnType, Body], Nodes),
  forall_member_node(ParamMembers),
  is_type_node(ReturnType), !.

forall_member_node([]).
forall_member_node([node(member, _) | Ms]) :- forall_member_node(Ms).

lower_param(node(member, Ch), parameter_node(Pattern, Annotation, Span)) :-
  child_nodes(Ch, ValueGreens0), exclude_type_node(ValueGreens0, [NameGreen]),
  green_to_binding(NameGreen, Pattern),
  member_annotation(Ch, Annotation),
  gspan(node(member, Ch), Span).

maplist_lower_param([], []).
maplist_lower_param([G | Gs], [P | Ps]) :- lower_param(G, P), maplist_lower_param(Gs, Ps).

% ===========================================================================
% match arms and patterns.
% ===========================================================================
maplist_lower_arm([], []).
maplist_lower_arm([G | Gs], [A | As]) :- lower_arm(G, A), maplist_lower_arm(Gs, As).

lower_arm(node(arm, Ch), match_arm([Pattern], no_guard, Result, Span)) :-
  child_nodes(Ch, [PatGreen, ResultGreen]),
  lower_match_pattern(PatGreen, Pattern),
  lower_expr(ResultGreen, Result),
  gspan(node(arm, Ch), Span).

lower_match_pattern(node(wildcard_pattern, Ch), wildcard_pattern(Span)) :- !, gspan(node(wildcard_pattern, Ch), Span).
lower_match_pattern(node(literal_pattern, Ch), literal_pattern(Lit, Span)) :- !,
  ( child_token(Ch, number, t(number, Text, NS, NE)) -> number_value(Text, V), Lit = number_node(V, span(NS, NE))
  ; child_token(Ch, string, t(string, Text, SS, SE)) -> string_parts(Text, Parts), Lit = string_node(Parts, span(SS, SE)) ),
  gspan(node(literal_pattern, Ch), Span).
lower_match_pattern(node(binding_pattern, Ch), binding_pattern(Name, Span)) :- !,
  child_token(Ch, ident, t(ident, Name, _, _)), gspan(node(binding_pattern, Ch), Span).
lower_match_pattern(node(constructor_pattern, Ch), constructor_pattern(Name, Subs, Span)) :- !,
  child_token(Ch, ident, t(ident, Name, _, _)),
  child_nodes(Ch, SubGreens),
  maplist_lower_match_pattern(SubGreens, Subs),
  gspan(node(constructor_pattern, Ch), Span).
lower_match_pattern(node(tuple_pattern, Ch), record_pattern(Members, Span)) :- !,
  child_nodes(Ch, SubGreens),
  maplist_lower_positional(SubGreens, Members),
  gspan(node(tuple_pattern, Ch), Span).
lower_match_pattern(Green, error_node(Span)) :- gspan(Green, Span).

maplist_lower_match_pattern([], []).
maplist_lower_match_pattern([G | Gs], [P | Ps]) :- lower_match_pattern(G, P), maplist_lower_match_pattern(Gs, Ps).

maplist_lower_positional([], []).
maplist_lower_positional([G | Gs], [positional_member_pattern(P, Span) | Ps]) :-
  lower_match_pattern(G, P), gspan(G, Span), maplist_lower_positional(Gs, Ps).

% ===========================================================================
% Reader-macro helpers.
% ===========================================================================
% The name is the dotted run of ident tokens before the `(`.
macro_call_name(Ch, Name) :-
  append(_, [t('@', _, _, _) | After], Ch), !,
  name_run(After, NameToks),
  collect_text(NameToks, Name).

name_run([t(ident, Tx, S, E) | Ts], [t(ident, Tx, S, E) | Rest]) :- !, name_run_dot(Ts, Rest).
name_run(_, []).
name_run_dot([t('.', Tx, S, E) | Ts], [t('.', Tx, S, E) | Rest]) :- !, name_run(Ts, Rest).
name_run_dot(_, []).

% Macro args are the sub-nodes EXCEPT the last (which is the following expr).
macro_call_args(Ch, Args) :- child_nodes(Ch, Nodes), append(Args, [_Following], Nodes).
% The following expression is the LAST sub-node; its raw source is its text
% with surrounding trivia trimmed.
macro_call_following(Ch, Source) :-
  child_nodes(Ch, Nodes), append(_, [Following], Nodes),
  leaves(Following, Ls), my_exclude(trivia_leaf, Ls, Sig),
  collect_text(Sig, Source).

% ===========================================================================
% External / type declaration / type expressions.
% ===========================================================================
lower_external(node(external, Ch), external_node(Name, Type, Source, Span)) :-
  item_name(Ch, Name),
  child_nodes(Ch, Nodes), Nodes = [TypeGreen | _],
  lower_type(TypeGreen, Type),
  external_source(Ch, Source),
  gspan(node(external, Ch), Span).

external_source(Ch, js_expression(Js)) :-
  child_token(Ch, '=', _), child_token(Ch, string, t(string, Text, _, _)), !,
  string_raw(Text, Js).
external_source(_Ch, js_global).

lower_type_declaration(node(type_declaration, Ch), type_declaration_node(Name, Parameters, Opacity, Body, Span)) :-
  item_name(Ch, Name),
  ( member(node(type_params, PCh), Ch) -> lower_type_params(node(type_params, PCh), Parameters)
  ; Parameters = [] ),
  ( member(node(variant, _), Ch) ->
      % `Opacity` is unused for a variant body (it is always nominal).
      Opacity = transparent,
      findall(Ctor, ( member(node(variant, VCh), Ch), lower_constructor(VCh, Ctor) ), Ctors),
      Body = variant_body(Ctors)
  ; member(node(opaque, _), Ch) ->
      Opacity = opaque, body_type_node(Ch, TypeGreen), lower_type(TypeGreen, Body)
  ; Opacity = transparent, body_type_node(Ch, TypeGreen), lower_type(TypeGreen, Body) ),
  gspan(node(type_declaration, Ch), Span).

% The alias body type node: the sole type node among the declaration's children
% once the type-parameter list and the `opaque` marker are removed.
body_type_node(Ch, TypeNode) :-
  child_nodes(Ch, Nodes),
  my_exclude(decl_meta_node, Nodes, [TypeNode | _]).
decl_meta_node(node(type_params, _)).
decl_meta_node(node(opaque, _)).

lower_constructor(VCh, constructor(Name, ArgTypes, Span)) :-
  child_token(VCh, ident, t(ident, Name, _, _)),
  child_nodes(VCh, ArgGreens),
  maplist_lower_type(ArgGreens, ArgTypes),
  variant_span(VCh, Span).
variant_span(VCh, span(S, E)) :-
  leaves(node(x, VCh), Ls), my_exclude(trivia_leaf, Ls, Sig),
  Sig = [t(_, _, _, _) | _],
  % span from the constructor ident to the last significant leaf
  child_token(VCh, ident, t(ident, _, S, _)),
  append(_, [t(_, _, _, E)], Sig).

% A named reference, with its (possibly qualified) name and any `<...>` args.
lower_type(node(type_name, Ch), type_name_node(Name, Arguments, Span)) :- !,
  qualified_name_text(Ch, Name),
  ( member(node(type_args, ACh), Ch) -> lower_type_arguments(ACh, Arguments) ; Arguments = [] ),
  gspan(node(type_name, Ch), Span).
% A quantified (polymorphic) type:  <params> body.
lower_type(node(quantified_type, [ParamsNode, BodyNode]), quantified_type_node(Parameters, Body, Span)) :- !,
  lower_type_params(ParamsNode, Parameters),
  lower_type(BodyNode, Body),
  gspan(node(quantified_type, [ParamsNode, BodyNode]), Span).
% A type hole `_` (only valid inside type arguments; carries a span).
lower_type(node(type_hole, Ch), type_hole(Span)) :- !,
  gspan(node(type_hole, Ch), Span).
% A tuple / record type, possibly open (`.. R?`).
lower_type(node(type_tuple, Ch), tuple_type_node(Members, Openness, Span)) :- !,
  findall(M, ( member(node(type_member, MCh), Ch), lower_type_member(MCh, M) ), Members),
  tuple_openness(Ch, Openness),
  gspan(node(type_tuple, Ch), Span).
% A function type:  ( params ) : return.  The first node is the parameter
% tuple, the last node is the return type; parameters are the member TYPES.
lower_type(node(function_type, Ch), function_type_node(ParamTypes, ReturnType, Span)) :- !,
  child_nodes(Ch, Nodes),
  Nodes = [ParamG | _], append(_, [ReturnG], Nodes),
  ( ParamG = node(type_tuple, PCh) ->
      findall(PT, ( member(node(type_member, MCh), PCh), member_type_node(MCh, TypeNode), lower_type(TypeNode, PT) ), ParamTypes)
  ; lower_type(ParamG, PT), ParamTypes = [PT] ),
  lower_type(ReturnG, ReturnType),
  gspan(node(function_type, Ch), Span).
lower_type(Green, type_name_node([], [], Span)) :- gspan(Green, Span).

maplist_lower_type([], []).
maplist_lower_type([G | Gs], [T | Ts]) :- lower_type(G, T), maplist_lower_type(Gs, Ts).

% The (possibly qualified) name of a type reference: concatenate the ident and
% `.` leaves in order (`math` `.` `Option` -> "math.Option"); the `<...>` args
% live in a `type_args` sub-node and so are excluded.
qualified_name_text(Ch, Name) :-
  findall(Text, ( member(t(K, Text, _, _), Ch), name_leaf_kind(K) ), Parts),
  concat_chars(Parts, Name).
name_leaf_kind(ident).
name_leaf_kind('.').

concat_chars([], []).
concat_chars([P | Ps], All) :- concat_chars(Ps, Rest), append(P, Rest, All).

% Type arguments: each is a type expression or a hole `_`.
lower_type_arguments(ACh, Arguments) :-
  child_nodes(ACh, Nodes),
  maplist_lower_type(Nodes, Arguments).

% A tuple type member: mutability (default readonly), an optional label, and the
% member's type.  Mutability and label sit in their own wrapper nodes.
lower_type_member(MCh, tuple_type_member(Mutability, Label, Type, Span)) :-
  ( member(node(mutability, MutCh), MCh), child_token(MutCh, ident, t(ident, "mutable", _, _)) -> Mutability = mutable
  ; Mutability = readonly ),
  ( member(node(type_label, LCh), MCh) -> child_token(LCh, ident, t(ident, LName, _, _)), Label = labeled(LName)
  ; Label = positional ),
  member_type_node(MCh, TypeNode),
  lower_type(TypeNode, Type),
  gspan(node(type_member, MCh), Span).

% The type expression of a member is its last sub-node (after any mutability /
% label wrapper nodes).
member_type_node(MCh, TypeNode) :-
  child_nodes(MCh, Nodes),
  my_exclude(member_meta_node, Nodes, [TypeNode | _]).
member_meta_node(node(mutability, _)).
member_meta_node(node(type_label, _)).

% Openness from a `type_rest` node: a captured rest `..R` names a row variable,
% an anonymous `..` is open, and no `type_rest` means a closed record.
tuple_openness(Ch, Openness) :-
  ( member(node(type_rest, RCh), Ch) ->
      ( child_token(RCh, ident, t(ident, RName, _, _)) -> Openness = open(capture(RName))
      ; Openness = open(anonymous) )
  ; Openness = closed ).

% Type parameters -> a list of `type_parameter(Name, Kind, Bound, Span)`.
lower_type_params(node(type_params, PCh), Parameters) :-
  findall(P, ( member(node(type_param, TPCh), PCh), lower_type_param(TPCh, P) ), Parameters).

lower_type_param(TPCh, type_parameter(Name, Kind, Bound, Span)) :-
  child_token(TPCh, ident, t(ident, Name, _, _)),
  ( member(node(type_param_kind, KCh), TPCh) ->
      hole_count(KCh, Kind), Bound = no_bound
  ; child_nodes(TPCh, [BoundNode]) ->
      Kind = 0, lower_type(BoundNode, BoundType), Bound = bound(BoundType)
  ; Kind = 0, Bound = no_bound ),
  gspan(node(type_param, TPCh), Span).

hole_count(KCh, N) :-
  findall(x, member(t(underscore, _, _, _), KCh), Holes),
  length(Holes, N).

% ===========================================================================
% Numbers and strings (recover values / parts from raw token text).
% ===========================================================================

% Reuse the real numeric grammar to convert text -> value (set_input_length so
% its span computation has a length; we ignore the span).
number_value(Text, Value) :-
  set_input_length(Text),
  once(phrase(number_literal(number_node(Value, _)), Text)).

% Strings: strip the surrounding quotes, then split into static / interpolated
% parts, processing `\'` `\\` `\{` escapes, mirroring string_literal.pl.
string_parts(['\'' | Rest], Parts) :-
  append(Body, ['\''], Rest), !,
  string_body_parts(Body, [string_static_part([])], Parts).
string_parts(Text, [string_static_part(Text)]).      % unterminated: take as-is

string_body_parts([], Parts, Parts).
string_body_parts(['\\', C | Cs], Parts0, Parts) :- !,
  ( member(C, ['\'', '{', '\\']) -> Ch = C ; Ch = C ),
  add_static_char(Ch, Parts0, Parts1),
  string_body_parts(Cs, Parts1, Parts).
string_body_parts(['{' | Cs], Parts0, Parts) :- !,
  take_balanced(Cs, 1, Inner, Rest),
  parse_interpolation(Inner, Expr),
  append(Parts0, [string_interpolated_part(Expr)], Parts1),
  string_body_parts(Rest, Parts1, Parts).
string_body_parts([C | Cs], Parts0, Parts) :-
  add_static_char(C, Parts0, Parts1),
  string_body_parts(Cs, Parts1, Parts).

% Append a char to the last part if it is static, else start a new static part.
add_static_char(C, Parts0, Parts) :-
  ( append(Init, [string_static_part(Text)], Parts0) ->
      append(Text, [C], Text1), append(Init, [string_static_part(Text1)], Parts)
  ; append(Parts0, [string_static_part([C])], Parts) ).

take_balanced(['}' | Cs], 1, [], Cs) :- !.
take_balanced(['}' | Cs], D, ['}' | Inner], Rest) :- D > 1, !, D1 is D - 1, take_balanced(Cs, D1, Inner, Rest).
take_balanced(['{' | Cs], D, ['{' | Inner], Rest) :- !, D1 is D + 1, take_balanced(Cs, D1, Inner, Rest).
take_balanced([C | Cs], D, [C | Inner], Rest) :- take_balanced(Cs, D, Inner, Rest).
take_balanced([], _D, [], []).

% Parse an interpolation's inner text into an AST (via the same front-end).
parse_interpolation(Inner, Expr) :-
  tokenize(Inner, Tokens),
  parse_tokens(Tokens, node(program, Children), _),
  child_nodes(Children, [Green | _]),
  lower_expr(Green, Expr).

% Raw single-quoted JS fragment for `external` sources: strip the quotes.
string_raw(['\'' | Rest], Js) :- append(Js, ['\''], Rest), !.
string_raw(Text, Text).
