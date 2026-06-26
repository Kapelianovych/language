:- module(pattern, [
  pattern//2,
  record_pattern//2,
  irrefutable_pattern//2,
  irrefutable_record_pattern//2
]).

/*  pattern.pl  --  Patterns, shared by `match` arms, destructuring
    definitions, and function parameters.

    A pattern is one of:

        _                       wildcard (matches anything, binds nothing)
        Identifier              binding (binds the whole value to the name)
        NumberLiteral           literal match
        BooleanLiteral          literal match
        StringLiteral           literal match
        ( PatternMembers )      record pattern: matches a record and
                                destructures it; members are positional
                                sub-patterns or `label = sub-pattern`

    Produced AST:

        wildcard_pattern
        binding_pattern(NameCharacters)
        literal_pattern(LiteralNode)            number_node | boolean_node | string_node
        record_pattern(MemberPatterns)
            member: positional_member_pattern(Pattern)
                  | labeled_member_pattern(NameCharacters, Pattern)

    `pattern//2` takes the surrounding expression functor, used only to parse
    interpolation inside string-literal patterns.
*/

:- use_module(library(dcgs)).
:- use_module(number_literal, [number_literal//1]).
:- use_module(boolean_literal, [boolean_literal//1]).
:- use_module(string_literal, [string_literal//2]).
:- use_module(identifier, [identifier//1, qualified_identifier//1]).
:- use_module(separator, [
  separator//0,
  separators//0
]).

:- meta_predicate(pattern(2, ?, ?, ?)).
:- meta_predicate(record_pattern(2, ?, ?, ?)).
:- meta_predicate(irrefutable_pattern(2, ?, ?, ?)).
:- meta_predicate(irrefutable_record_pattern(2, ?, ?, ?)).

% Constructor first (`Name(...)`, distinguished from a binding by the
% parens), then record (`(`), literals, the wildcard `_`, and finally a
% binding (an identifier is the most general leaf).
pattern(ExpressionFunctor, Node) -->
  constructor_pattern(ExpressionFunctor, Node)
  | record_pattern(ExpressionFunctor, Node)
  | literal_pattern(ExpressionFunctor, Node)
  | wildcard_pattern(Node)
  | binding_pattern(Node).

% A tagged-union constructor pattern: `Circle(r)`, `Rect(w h)`, `None()`.
% (Nullary constructors are matched with empty parens, `None()`, so a bare
% identifier is unambiguously a binding.)  The name may be QUALIFIED
% (`Math.Some(v)`) when the constructor comes from a whole-module import.
constructor_pattern(ExpressionFunctor, constructor_pattern(Name, SubPatterns)) -->
  qualified_identifier(Name),
  "(",
  separators,
  constructor_sub_patterns(ExpressionFunctor, SubPatterns),
  separators,
  ")".

constructor_sub_patterns(_, []) --> [].
constructor_sub_patterns(ExpressionFunctor, [SubPattern | SubPatterns]) -->
  pattern(ExpressionFunctor, SubPattern),
  constructor_sub_patterns_tail(ExpressionFunctor, SubPatterns).

constructor_sub_patterns_tail(_, []) --> [].
constructor_sub_patterns_tail(ExpressionFunctor, [SubPattern | SubPatterns]) -->
  separator, % mandatory
  separators,
  pattern(ExpressionFunctor, SubPattern),
  constructor_sub_patterns_tail(ExpressionFunctor, SubPatterns).

wildcard_pattern(wildcard_pattern) -->
  "_".

binding_pattern(binding_pattern(Name)) -->
  identifier(identifier_node(Name)).

literal_pattern(_, literal_pattern(Node)) -->
  number_literal(Node)
  | boolean_literal(Node).
literal_pattern(ExpressionFunctor, literal_pattern(Node)) -->
  string_literal(ExpressionFunctor, Node).

record_pattern(ExpressionFunctor, record_pattern(Members)) -->
  "(",
  separators,
  pattern_members(ExpressionFunctor, Members),
  separators,
  ")".

pattern_members(_, []) --> [].
pattern_members(ExpressionFunctor, [Member | Members]) -->
  pattern_member(ExpressionFunctor, Member),
  pattern_members_tail(ExpressionFunctor, Members).

pattern_members_tail(_, []) --> [].
pattern_members_tail(ExpressionFunctor, [Member | Members]) -->
  separator, % mandatory
  separators,
  pattern_member(ExpressionFunctor, Member),
  pattern_members_tail(ExpressionFunctor, Members).

% A labeled member uses `=` (like a labeled tuple value `(x = 1)`), NOT `:`:
% `(x = p)` matches field `x` against sub-pattern `p`.  Using `=` avoids the
% trap of `(x: string)` reading like a typed binder.  Labeled is tried first.
pattern_member(ExpressionFunctor, Member) -->
  labeled_member_pattern(ExpressionFunctor, Member)
  | positional_member_pattern(ExpressionFunctor, Member).

labeled_member_pattern(ExpressionFunctor, labeled_member_pattern(Name, SubPattern)) -->
  identifier(identifier_node(Name)),
  separators,
  "=",
  separators,
  pattern(ExpressionFunctor, SubPattern).

positional_member_pattern(ExpressionFunctor, positional_member_pattern(SubPattern)) -->
  pattern(ExpressionFunctor, SubPattern).

% ---------------------------------------------------------------------------
% Irrefutable patterns -- used where a match cannot fail and so binds only
% (function parameters, destructuring definitions): no literal patterns.
% ---------------------------------------------------------------------------

irrefutable_pattern(ExpressionFunctor, Node) -->
  irrefutable_record_pattern(ExpressionFunctor, Node)
  | wildcard_pattern(Node)
  | binding_pattern(Node).

irrefutable_record_pattern(ExpressionFunctor, record_pattern(Members)) -->
  "(",
  separators,
  irrefutable_members(ExpressionFunctor, Members),
  separators,
  ")".

irrefutable_members(_, []) --> [].
irrefutable_members(ExpressionFunctor, [Member | Members]) -->
  irrefutable_member(ExpressionFunctor, Member),
  irrefutable_members_tail(ExpressionFunctor, Members).

irrefutable_members_tail(_, []) --> [].
irrefutable_members_tail(ExpressionFunctor, [Member | Members]) -->
  separator, % mandatory
  separators,
  irrefutable_member(ExpressionFunctor, Member),
  irrefutable_members_tail(ExpressionFunctor, Members).

irrefutable_member(ExpressionFunctor, labeled_member_pattern(Name, SubPattern)) -->
  identifier(identifier_node(Name)),
  separators,
  "=",
  separators,
  irrefutable_pattern(ExpressionFunctor, SubPattern).
irrefutable_member(ExpressionFunctor, positional_member_pattern(SubPattern)) -->
  irrefutable_pattern(ExpressionFunctor, SubPattern).
