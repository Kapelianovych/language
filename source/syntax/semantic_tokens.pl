:- module(semantic_tokens, [classify/2, token_type/2]).

/*  source/syntax/semantic_tokens.pl  --  LSP semantic-highlighting classifier.
    ========================================================================

    Walks the raw GREEN TREE (the same `node(Kind,Children)` / `t(Kind,Text,
    Start,End)` shape the parser produces, before `lower` throws away trivia
    and re-shapes it into the historical AST) and emits a flat, ALREADY-
    ORDERED list of `tok(Type, Start, End)` -- one entry per span the editor
    should colour.  "Already ordered": every rule below recurses over
    `Children` strictly left-to-right and never reorders or re-visits a span,
    so the output is naturally in ascending `Start` order with no sort step.

    WHY THE GREEN TREE, NOT THE LOWERED AST

      Semantic tokens are a per-KEYSTROKE, per-TOKEN concern -- every leaf in
      the source needs a colour (including keywords, punctuation-as-operator,
      and comments), which `lower` deliberately throws away.  The green tree
      already carries exact spans for every leaf, so no offset bookkeeping is
      needed beyond reading `Start`/`End` off the leaves themselves.

    WHY MOST OF THE TREE NEEDS NO SPECIAL CASE

      Two kinds of node are already self-describing regardless of where they
      sit in the tree:
        * TYPE-shaped nodes (`type_name`, `type_param`, `type_declaration`,
          `variant`, `module_type_member`, ...) only ever occur in a type
          position, so tagging them by their OWN kind is always right --  no
          "am I inside a type?" context needs to be threaded down from a
          parent.
        * Everything else defaults to a per-LEAF rule (`leaf_token/2`):
          keyword-by-text, or number/string/comment/operator by token kind,
          or `variable` for a plain `ident`.  This alone is already correct
          for the common case (an ordinary variable read, a literal, a
          keyword) with zero bookkeeping.

      The only genuine special cases are PARENT kinds whose CHILD occupies a
      role the green tree's shape does not otherwise reveal -- e.g. a bare
      `ident` LEAF (not wrapped in an `identifier` node) is a declared type
      name in `type_declaration` but a declared macro name in
      `macro_definition`; a function's parameter list and a record literal's
      member list both use the SAME `member` node shape but mean
      `parameter` in one and `variable`/`property` in the other.  Those are
      handled by dedicated `special/4` clauses below, each documented at its
      grammar rule's home in `parser.pl`.

    ROBUSTNESS:  every `special/4` clause commits (`!`) as soon as it matches
    its Kind, then may still FAIL if the assumed shape is not actually there
    (e.g. a parse-error-recovered node).  `emit/3`'s `( special(...) -> true
    ; emit_list(...) )` catches that failure and falls back to plain
    generic recursion, so a shape surprise degrades to "less precisely
    classified", never a crash.

    KNOWN IMPRECISIONS (acceptable for a v1):
      * Soft keywords (`use`, `type`, `mutable`, ...) are coloured `keyword`
        by TEXT ALONE wherever the generic leaf rule reaches them, even in
        the rare case they are used as an ordinary read of a same-named
        variable (the parser truly does allow this).  Declared NAMES (via
        `all_idents_as/4`) are unaffected -- they always get the role the
        parent asked for, never the keyword colour.
      * `obj.method(...)` colours `method` as `property` (the call rule only
        special-cases a direct `identifier` callee); `|` is always `operator`
        even when it is really an arm/variant separator.
*/

:- set_prolog_flag(double_quotes, chars).

:- use_module(library(lists)).

% `special/4`'s clauses are grouped by grammar rule (each next to its own
% helper predicates) rather than all adjacent, so without this Scryer treats
% each non-adjacent block as a fresh definition and SILENTLY DISCARDS the
% earlier ones (the standard "consecutive clauses" pitfall, just silent
% instead of an error) -- discovered the hard way via its own build-time
% warning ("overwriting special/4 because the clauses are discontiguous").
:- discontiguous(special/4).

% ===========================================================================
% Entry point.
% ===========================================================================

% classify(+GreenTree, -Tokens): Tokens is an ascending-Start list of
% tok(Type, Start, End).  Type is one of the atoms `token_type/2` maps to a
% legend index (see lsp.pl), the LSP semantic-token-type name.
classify(Tree, Tokens) :- emit(Tree, Tokens, []).

% The legend, in LEGEND-INDEX order.  lsp.pl sends this verbatim as the
% `initialize` response's `semanticTokensProvider.legend.tokenTypes`.
token_type(namespace,     0).
token_type(type,          1).
token_type(typeParameter, 2).
token_type(parameter,     3).
token_type(variable,      4).
token_type(property,      5).
token_type(enumMember,    6).
token_type(function,      7).
token_type(method,        8).
token_type(macro,         9).
token_type(keyword,       10).
token_type(comment,       11).
token_type(string,        12).
token_type(number,        13).
token_type(operator,      14).

% ===========================================================================
% Generic dispatch: a leaf classifies itself; a node tries a `special/4`
% override for its Kind, falling back to plain per-child recursion.
% ===========================================================================

emit(t(Kind, Text, S, E), Toks, Tail) :- !,
  ( leaf_token(t(Kind, Text, S, E), Tok) -> Toks = [Tok | Tail] ; Toks = Tail ).
emit(node(Kind, Children), Toks, Tail) :-
  ( special(Kind, Children, Toks, Tail) -> true
  ; emit_list(Children, Toks, Tail) ).

emit_list([], Tail, Tail).
emit_list([C | Cs], Toks, Tail) :-
  emit(C, Toks, Mid),
  emit_list(Cs, Mid, Tail).

% ---------------------------------------------------------------------------
% Per-leaf default: keyword-by-text for an `ident`, kind-based for a literal /
% comment / real operator; everything else (whitespace, `missing`, `eof`,
% `_`, pure structural punctuation) contributes no token.
% ---------------------------------------------------------------------------

leaf_token(t(comment, _, S, E), tok(comment, S, E)).
leaf_token(t(string, _, S, E), tok(string, S, E)).
leaf_token(t(number, _, S, E), tok(number, S, E)).
leaf_token(t(ident, Text, S, E), tok(Type, S, E)) :- ident_type(Text, Type).
leaf_token(t(Kind, _, S, E), tok(operator, S, E)) :- operator_kind(Kind).

ident_type(Text, keyword) :- keyword_word(Text), !.
ident_type(_, variable).

% The soft-keyword texts (see parser.pl's "SOFT KEYWORDS" note) plus the two
% boolean literals, which parse as plain `ident`/`identifier` outside of
% patterns (see `literal_pattern` in parser.pl) and so only get coloured here.
keyword_word("else"). keyword_word("external"). keyword_word("false").
keyword_word("from"). keyword_word("if"). keyword_word("macro").
keyword_word("match"). keyword_word("module"). keyword_word("mutable").
keyword_word("opaque"). keyword_word("public"). keyword_word("true").
keyword_word("type"). keyword_word("use").

% Real operators only (see parser.pl's `unary_operator/1` and
% `binary_operator/3` tables) -- structural punctuation (`(` `)` `{` `}` `,`
% `:` `@` `` ` `` `~`) is deliberately left uncoloured.
operator_kind('-'). operator_kind('!'). operator_kind('!!').
operator_kind('*'). operator_kind('/'). operator_kind('+').
operator_kind('<<'). operator_kind('>>'). operator_kind('&&').
operator_kind('^^'). operator_kind('||'). operator_kind('<=').
operator_kind('<'). operator_kind('>='). operator_kind('>').
operator_kind('=='). operator_kind('!='). operator_kind('&').
operator_kind('^'). operator_kind('|'). operator_kind('->').
operator_kind('=').

% Punctuation kinds checked below via unification against a fact's argument,
% never `==` against the bare atom -- the same hazard `parser.pl`'s `punct/2`
% exists to avoid (a quoted operator atom as an `==` operand trips Scryer's
% reader with `incomplete_reduction`).
leaf_kind_atom(dot,         '.').
leaf_kind_atom(open_paren,  '(').
leaf_kind_atom(close_paren, ')').
leaf_kind_atom(colon,       ':').
leaf_kind_atom(open_angle,  '<').
leaf_kind_atom(close_angle, '>').

is_dot(K)         :- leaf_kind_atom(dot, K).
is_open_paren(K)  :- leaf_kind_atom(open_paren, K).
is_close_paren(K) :- leaf_kind_atom(close_paren, K).
is_colon(K)       :- leaf_kind_atom(colon, K).
is_angle(K)       :- leaf_kind_atom(open_angle, K).
is_angle(K)       :- leaf_kind_atom(close_angle, K).

% ===========================================================================
% Shared scanning helpers.  These all work over a flat green-tree Children
% list (leaves and nodes interleaved, exactly as the parser built it) and
% thread a Toks/Tail difference-list pair alongside a "Rest" cursor.
% ===========================================================================

% all_idents_as(+Type, +Children, Toks, Tail): every raw `ident` LEAF found
% is tagged Type UNCONDITIONALLY (bypassing `keyword_word` -- a name being
% DECLARED here, e.g. a parameter literally called "type", is never the
% keyword).  Any node is recursed generically (needed so a destructuring
% `group` nested inside a parameter list still gets walked); any other leaf
% falls back to the ordinary per-leaf default.
all_idents_as(_, [], Tail, Tail).
all_idents_as(Type, [t(ident, _, S, E) | Rest], [tok(Type, S, E) | Toks], Tail) :- !,
  all_idents_as(Type, Rest, Toks, Tail).
all_idents_as(Type, [Other | Rest], Toks, Tail) :-
  emit(Other, Toks, Mid),
  all_idents_as(Type, Rest, Mid, Tail).

% ident_run_as(+Type, +Children, Toks, Tail, -After): tag a maximal run of
% `ident`/`.` leaves (a possibly-qualified name -- `use` paths, macro names,
% constructor-pattern names, `type_name`'s own segments) as Type, skipping
% whitespace/comments WITHIN the run; stop at the first leaf/node that is
% neither, returning it (and everything after) unconsumed in `After` for the
% caller to keep walking generically.
ident_run_as(_, [], Tail, Tail, []).
ident_run_as(Type, [t(ident, _, S, E) | Rest], [tok(Type, S, E) | Toks], Tail, After) :- !,
  ident_run_as(Type, Rest, Toks, Tail, After).
ident_run_as(Type, [t(K, _, _, _) | Rest], Toks, Tail, After) :-
  is_dot(K), !,
  ident_run_as(Type, Rest, Toks, Tail, After).
ident_run_as(Type, [t(comment, _, S, E) | Rest], [tok(comment, S, E) | Toks], Tail, After) :- !,
  ident_run_as(Type, Rest, Toks, Tail, After).
ident_run_as(Type, [t(whitespace, _, _, _) | Rest], Toks, Tail, After) :- !,
  ident_run_as(Type, Rest, Toks, Tail, After).
ident_run_as(_, Rest, Toks, Toks, Rest).

% use_path_run(+Children, Toks, Tail, -After): a `use` PATH (see `path/3`) is
% "the maximal run of contiguous significant tokens that are neither `:` nor
% end-of-input" -- NOT just idents/dots, e.g. `./math` also has a `/`.  Every
% significant leaf in that run is coloured `namespace`; stops at the first
% `:` (import list follows) or trivia run boundary, same as `path/3` itself.
% `path/3` prepends the ONE trivia run between `use` and the path itself into
% its own Children, so that has to be skipped (not treated as "path already
% ended") before this loop's own stop-on-trivia rule can mean what it says.
use_path_run(Children, Toks, Tail, After) :-
  skip_leading_trivia(Children, Toks, Mid, Rest),
  use_path_run_(Rest, Mid, Tail, After).

skip_leading_trivia([Leaf | Rest], Toks, Tail, After) :-
  Leaf = t(K, _, _, _), ( K == whitespace ; K == comment ), !,
  emit(Leaf, Toks, Mid),
  skip_leading_trivia(Rest, Mid, Tail, After).
skip_leading_trivia(Rest, Toks, Toks, Rest).

use_path_run_([], Tail, Tail, []).
use_path_run_([Leaf | Rest], Toks, Tail, After) :-
  Leaf = t(K, _, S, E),
  ( ( K == whitespace ; K == comment ; is_colon(K) ) ->
      Toks = Tail, After = [Leaf | Rest]
  ; Toks = [tok(namespace, S, E) | Toks1], use_path_run_(Rest, Toks1, Tail, After) ).

% skip_non_ident(+Children, Toks, Tail, -After): generically emit leading
% leaves/nodes (trivia, a leading `@`/`~`/keyword-not-yet-reached) up to --
% but not including -- the first raw `ident` leaf.
skip_non_ident([], Tail, Tail, []).
skip_non_ident([Leaf | Rest], Toks, Tail, [Leaf | Rest]) :-
  Leaf = t(ident, _, _, _), !, Toks = Tail.
skip_non_ident([Other | Rest], Toks, Tail, After) :-
  emit(Other, Toks, Mid),
  skip_non_ident(Rest, Mid, Tail, After).

% named_then_rest(+Type, +Children, Toks, Tail): Children begins (after any
% leading trivia) with the ONE `ident` leaf being declared/named; tag it
% Type, then walk everything else generically (it is either self-classifying
% nodes -- a type, a bound, a body -- or structural leaves).
named_then_rest(Type, Children, Toks, Tail) :-
  skip_non_ident(Children, Toks, T1, [NameLeaf | Rest]),
  ( NameLeaf = t(ident, _, S, E) -> T1 = [tok(Type, S, E) | T2] ; emit(NameLeaf, T1, T2) ),
  emit_list(Rest, T2, Tail).

% single_keyword_then_name(+Type, +Children, Toks, Tail): like
% `named_then_rest/4`, but Children leads with the FORM's own keyword ident
% (`type`, `external`, `module`, `macro`) before the declared name -- the
% keyword is emitted through the ordinary generic path (so it gets coloured
% `keyword` by `keyword_word/1`, exactly as if no special rule existed here).
single_keyword_then_name(Type, Children, Toks, Tail) :-
  skip_non_ident(Children, Toks, T1, [KwLeaf | Rest]),
  emit(KwLeaf, T1, T2),
  named_then_rest(Type, Rest, T2, Tail).

% parens_split(+Children, -Before, -Inside, -After): split a flat Children
% list at its OWN (unnested -- a nested one belongs to a child node) `(` and
% matching `)` leaves.  Used for a `function`'s parameter list and a
% `macro_definition`'s parameter list, both `NAME ... "(" params ")" ...`.
parens_split(Children, Before, Inside, After) :-
  append(Before, [Open | Rest1], Children), Open = t(OK, _, _, _), is_open_paren(OK), !,
  append(Inside, [Close | After], Rest1), Close = t(CK, _, _, _), is_close_paren(CK), !.

% first_node(+Children, -Node): the first child that is an internal node
% (skipping leaves) -- used to peek at a declaration's TYPE without caring
% exactly how many leaves (keyword, name, `:`) precede it.
first_node([Node | _], Node) :- Node = node(_, _), !.
first_node([_ | Rest], Node) :- first_node(Rest, Node).

is_function_shaped(node(function_type, _)).
is_function_shaped(node(quantified_type, [_, Body])) :- is_function_shaped(Body).

% ===========================================================================
% Special cases.  Each corresponds to exactly one grammar rule in
% `source/syntax/parser.pl` (named in the comment); see that file for the
% Children shape being relied on here.
% ===========================================================================

% type_reference/5: a (possibly-qualified, possibly-generic) type name.
special(type_name, Children, Toks, Tail) :- !,
  ident_run_as(type, Children, Toks, Mid, After),
  emit_list(After, Mid, Tail).

% type_parameter/5: `Name` | `Name<_.._>` | `Name: Bound`.
special(type_param, Children, Toks, Tail) :- !,
  named_then_rest(typeParameter, Children, Toks, Tail).

% type_member/5's label wrapper: `Identifier ":"` before a record/record
% type's member type.
special(type_label, Children, Toks, Tail) :- !,
  named_then_rest(property, Children, Toks, Tail).

% type_declaration/5: `type NAME <params>? = body`.
special(type_declaration, Children, Toks, Tail) :- !,
  single_keyword_then_name(type, Children, Toks, Tail).

% module_declaration/5: `opaque? module NAME <params>? (: ModuleType)? = { ... }`.
% The optional leading `opaque` is already its own `node(opaque,_)` (not a
% raw leaf), so it does not interfere with "skip the ONE keyword ident,
% then tag the name".
special(module, Children, Toks, Tail) :- !,
  single_keyword_then_name(namespace, Children, Toks, Tail).

% macro_declaration/5: `macro NAME = ( params ) BODY` (bare parameter names,
% no annotations -- reuses `name_list/5`, so params are RAW idents).
special(macro_definition, Children, Toks, Tail) :- !,
  skip_non_ident(Children, Toks, T1, [KwLeaf | Rest0]),
  emit(KwLeaf, T1, T2),
  skip_non_ident(Rest0, T2, T3, [NameLeaf | Rest1]),
  ( NameLeaf = t(ident, _, S, E) -> T3 = [tok(macro, S, E) | T4] ; emit(NameLeaf, T3, T4) ),
  parens_split(Rest1, Before, Inside, After),
  emit_list(Before, T4, T5),
  all_idents_as(parameter, Inside, T5, T6),
  emit_list(After, T6, Tail).

% macro_invocation/5: `@NAME(...)` / `@Mod.name(...)`, NAME possibly dotted.
special(macro_call, Children, Toks, Tail) :- !,
  skip_non_ident(Children, Toks, T1, After0),
  % `skip_non_ident` stops at the first `ident` leaf; there is none before
  % the name here (only the leading `@` and trivia), so `After0` already
  % starts at the name -- reuse `ident_run_as` for the (possibly dotted) run.
  ident_run_as(macro, After0, T1, T2, After1),
  emit_list(After1, T2, Tail).

% external_declaration/5: `external NAME : TYPE (= 'src')? (from 'mod')?`.
special(external, Children, Toks, Tail) :- !,
  skip_non_ident(Children, Toks, T1, [KwLeaf | Rest0]),
  emit(KwLeaf, T1, T2),
  skip_non_ident(Rest0, T2, T3, [NameLeaf | Rest1]),
  ( first_node(Rest1, TypeNode), is_function_shaped(TypeNode) -> EType = function ; EType = variable ),
  ( NameLeaf = t(ident, _, S, E) -> T3 = [tok(EType, S, E) | T4] ; emit(NameLeaf, T3, T4) ),
  emit_list(Rest1, T4, Tail).

% module_type_member/5: `NAME : TYPE` inside a `type X = { ... }` module type body.
special(module_type_member, Children, Toks, Tail) :- !,
  skip_non_ident(Children, Toks, T1, [NameLeaf | Rest]),
  ( first_node(Rest, TypeNode), is_function_shaped(TypeNode) -> IType = method ; IType = property ),
  ( NameLeaf = t(ident, _, S, E) -> T1 = [tok(IType, S, E) | T2] ; emit(NameLeaf, T1, T2) ),
  emit_list(Rest, T2, Tail).

% constructor_node/5: a variant's constructor, e.g. `Some(A)` in
% `type Option<A> = None | Some(A)`.
special(variant, Children, Toks, Tail) :- !,
  ident_run_as(enumMember, Children, Toks, Mid, After),
  emit_list(After, Mid, Tail).

% pattern/5's constructor-pattern branch: `math.Some(v)` / `math.None`, name
% possibly qualified.
special(constructor_pattern, Children, Toks, Tail) :- !,
  ident_run_as(enumMember, Children, Toks, Mid, After),
  emit_list(After, Mid, Tail).

% pattern_member_sequence/5's labeled branch: `x = pattern` inside a record
% pattern `(x = p)`.
special(labeled_pattern, Children, Toks, Tail) :- !,
  named_then_rest(property, Children, Toks, Tail).

% use_declaration/5: `use PATH` / `use PATH:(a b c)`.  PATH (a run of
% non-trivia, non-`:` tokens -- see `path/3`) is coloured `namespace`;
% imported names after `:(...)` are left at their generic default.
special(use, Children, Toks, Tail) :- !,
  skip_non_ident(Children, Toks, T1, [KwLeaf | Rest0]),
  emit(KwLeaf, T1, T2),
  use_path_run(Rest0, T2, T3, After),
  emit_list(After, T3, Tail).

% type_parameters/5 and type_arguments/5: `<...>` around params/arguments --
% the brackets are structural (not the comparison operator, even though they
% share its token Kind), so they are dropped rather than left to the generic
% leaf default (which would colour them `operator`).  `kind_holes/5`'s own
% `<...>` (a higher-kinded parameter's `F<_ _>`) gets the same treatment.
special(type_params, Children, Toks, Tail) :- !,
  drop_angle_leaves(Children, Inner), emit_list(Inner, Toks, Tail).
special(type_args, Children, Toks, Tail) :- !,
  drop_angle_leaves(Children, Inner), emit_list(Inner, Toks, Tail).
special(type_param_kind, Children, Toks, Tail) :- !,
  drop_angle_leaves(Children, Inner), emit_list(Inner, Toks, Tail).

drop_angle_leaves([], []).
drop_angle_leaves([t(K, _, _, _) | Rest], Inner) :- is_angle(K), !, drop_angle_leaves(Rest, Inner).
drop_angle_leaves([Other | Rest], [Other | Inner]) :- drop_angle_leaves(Rest, Inner).

% postfix_chain/6's `.access` branch: `Acc.name` / `Acc.0` (a positional
% record accessor -- see `accessor/5` -- falls through to the plain `number`
% default since only a trailing `ident` is overridden here).
special(access, [Acc | RestLeaves], Toks, Tail) :- !,
  emit(Acc, Toks, Mid),
  access_tail(RestLeaves, Mid, Tail).

access_tail([], Tail, Tail).
access_tail([t(ident, _, S, E) | Rest], [tok(property, S, E) | Toks], Tail) :- !,
  access_tail(Rest, Toks, Tail).
access_tail([Other | Rest], Toks, Tail) :-
  emit(Other, Toks, Mid),
  access_tail(Rest, Mid, Tail).

% postfix_chain/6's call branch: `callee(args)` / `callee<T>(args)` -- only a
% direct `identifier` callee is coloured `function`; an `access`/`group`/...
% callee is recursed normally (see the "KNOWN IMPRECISIONS" note above).
special(call, [Callee | Rest], Toks, Tail) :- !,
  ( Callee = node(identifier, Ch) -> all_idents_as(function, Ch, Toks, Mid) ; emit(Callee, Toks, Mid) ),
  emit_list(Rest, Mid, Tail).

% postfix_chain/6's standalone type-application branch: `Stack<number>` with
% no call following -- the callee position is a TYPE, not a value.
special(type_apply, [Acc, TypeArgsNode], Toks, Tail) :- !,
  emit_as_type(Acc, Toks, Mid),
  emit(TypeArgsNode, Mid, Tail).

emit_as_type(node(identifier, Ch), Toks, Tail) :- !, all_idents_as(type, Ch, Toks, Tail).
emit_as_type(node(access, [Acc | RestLeaves]), Toks, Tail) :- !,
  emit_as_type(Acc, Toks, Mid),
  access_tail_as_type(RestLeaves, Mid, Tail).
emit_as_type(Other, Toks, Tail) :- emit(Other, Toks, Tail).

access_tail_as_type([], Tail, Tail).
access_tail_as_type([t(ident, _, S, E) | Rest], [tok(type, S, E) | Toks], Tail) :- !,
  access_tail_as_type(Rest, Toks, Tail).
access_tail_as_type([Other | Rest], Toks, Tail) :-
  emit(Other, Toks, Mid),
  access_tail_as_type(Rest, Mid, Tail).

% infix_loop/6's `=` branch: `Left = Right` (a top-level/block statement or
% an assignment/destructuring -- a bare `identifier` Left is the only shape
% that needs a decision: `function` when Right is a function literal
% (through `paren_or_function`/`generic_function`, both produce `node
% (function,_)`), else `variable`.  An `access` Left (assignment) or `group`
% Left (destructuring) is recursed generically -- their own special rules
% (`access`, `group` via `member` below) already do the right thing.
special(definition, [Left | Rest], Toks, Tail) :- !,
  ( Left = node(identifier, Ch) ->
      ( append(_, [Right], Rest), is_function_like(Right) -> DType = function ; DType = variable ),
      all_idents_as(DType, Ch, Toks, Mid)
  ; emit(Left, Toks, Mid) ),
  emit_list(Rest, Mid, Tail).

is_function_like(node(function, _)).

% paren_or_function/5's parameter section: every `member`/`spread`/`error`
% node between the `function`'s own `(` and `)` is a PARAMETER, not a value
% -- including names nested inside a destructuring `group`.
special(function, Children, Toks, Tail) :- !,
  parens_split(Children, Before, Inside, After),
  emit_list(Before, Toks, Mid1),
  emit_param_members(Inside, Mid1, Mid2),
  emit_list(After, Mid2, Tail).

emit_param_members([], Tail, Tail).
emit_param_members([node(member, MCh) | Rest], Toks, Tail) :- !,
  param_scan(MCh, Toks, Mid),
  emit_param_members(Rest, Mid, Tail).
emit_param_members([Other | Rest], Toks, Tail) :-
  emit(Other, Toks, Mid),
  emit_param_members(Rest, Mid, Tail).

param_scan([], Tail, Tail).
param_scan([node(identifier, Ch) | Rest], Toks, Tail) :- !,
  all_idents_as(parameter, Ch, Toks, Mid),
  param_scan(Rest, Mid, Tail).
param_scan([node(group, GCh) | Rest], Toks, Tail) :- !,
  % A destructuring parameter `((a b): (number number)) ...` -- GCh is the
  % group's own flat `(` params `)`; walking it with `emit_param_members/3`
  % (not the plain `group` rule) keeps every nested name `parameter`.
  emit_param_members(GCh, Toks, Mid),
  param_scan(Rest, Mid, Tail).
param_scan([node(definition, [Left | DRest]) | Rest], Toks, Tail) :- !,
  ( Left = node(identifier, IdCh) -> all_idents_as(parameter, IdCh, Toks, Mid1) ; emit(Left, Toks, Mid1) ),
  emit_list(DRest, Mid1, Mid),
  param_scan(Rest, Mid, Tail).
param_scan([Other | Rest], Toks, Tail) :-
  emit(Other, Toks, Mid),
  param_scan(Rest, Mid, Tail).

% member_sequence/5 as used by a record/record LITERAL (or a destructuring
% `definition` LHS) -- a `group`, never a `function`'s parameter list (that
% is intercepted by `special(function,...)` above before recursion ever
% reaches a bare `member` node here).  A labeled member `x = 1` names a
% FIELD (`property`); a bare member is an ordinary value read, left at its
% generic default (`variable` for an identifier).
special(group, Children, Toks, Tail) :- !,
  emit_group_children(Children, Toks, Tail).

emit_group_children([], Tail, Tail).
emit_group_children([node(member, MCh) | Rest], Toks, Tail) :- !,
  member_scan(MCh, Toks, Mid),
  emit_group_children(Rest, Mid, Tail).
emit_group_children([Other | Rest], Toks, Tail) :-
  emit(Other, Toks, Mid),
  emit_group_children(Rest, Mid, Tail).

member_scan([], Tail, Tail).
member_scan([node(definition, [Left | DRest]) | Rest], Toks, Tail) :- !,
  ( Left = node(identifier, IdCh) -> all_idents_as(property, IdCh, Toks, Mid1) ; emit(Left, Toks, Mid1) ),
  emit_list(DRest, Mid1, Mid),
  member_scan(Rest, Mid, Tail).
member_scan([Other | Rest], Toks, Tail) :-
  emit(Other, Toks, Mid),
  member_scan(Rest, Mid, Tail).
