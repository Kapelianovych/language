:- module(position, [
  here//1,
  set_input_length/1,
  span_between/3,
  zero_width_span_at/2,
  node_span/2,
  span_cover/3,
  offset/2
]).

/*  parser/position.pl  --  Source-offset capture for the DCG parser.

    Every AST node records a `span(Start, End)` so that downstream tools (LSP:
    hover, go-to-definition, diagnostics, selection ranges) and error reporting
    can point back at the exact source the node came from.  `Start` and `End`
    are 0-based CHARACTER offsets into the parsed input, with `End` EXCLUSIVE,
    measured over the meaningful token range (surrounding separators excluded --
    see "Excluding separators" below).

    WHY OFFSETS, NOT LINE/COLUMN

      Offsets are exact, cheap to capture, and stable under editing math.  The
      editor/LSP boundary converts an offset to a UTF-16 line/character position
      using a once-built line-start index; keeping line/column out of the AST
      avoids threading it through every rule and recomputing it on every edit.

    HOW POSITIONS ARE CAPTURED

      The parser is a scannerless DCG over a list of character atoms (see
      `parser.pl`).  At any point during parsing the "remaining input" is a
      SUFFIX of the whole input list.  The offset of a suffix is therefore

          offset(Suffix) = TotalLength - length(Suffix)

      `here//1` captures the current remaining-input suffix WITHOUT consuming
      anything (the classic DCG `here(L,L,L)` lookahead trick: all three
      difference-list arguments are unified, so input == output == the captured
      tail).  A node rule captures the suffix at its start and at its end and
      turns the two into a `span/2`:

          number_literal(number_node(N, Span)) -->
            here(Start), number_chars(N), here(End),
            { span_between(Start, End, Span) }.

      `TotalLength` is established once per parse by `set_input_length/1` (called
      from `parser.pl`) and held in the module-private dynamic fact
      `input_length/1`.  A dynamic fact (rather than threading the length
      through every rule as an extra argument) keeps every grammar rule's arity
      and the `phrase(ExpressionFunctor, ...)` meta-call plumbing untouched.
      Parsing is single-threaded, so the single fact is safe; `set_input_length/1`
      retracts any previous value first, so re-entrant parses each reset it.

    EXCLUDING SEPARATORS

      A node rule captures `here` at ITS OWN start and end.  Leading and trailing
      separators (whitespace / comments) are consumed BETWEEN items by
      `separators//0` -- outside the node rule -- so a span naturally brackets
      just the construct's own text.  Composite rules (e.g. `definition//2`)
      capture at rule entry and after their final subterm, so the span covers
      the whole construct from its first to its last character.

    PERFORMANCE

      `length(Suffix, _)` is O(length of the remaining input), so capturing a
      span near the FRONT of a large file is O(file size); over a whole file the
      worst case is O(n^2).  This is comfortably fast for typical source files.
      Because the AST stores integer offsets (not list tails), the COMPUTATION
      method can later be swapped for an O(n) approach (threading a monotonic
      counter, or a single post-pass) WITHOUT touching any AST consumer -- the
      `span(Start, End)` representation is the stable contract.
*/

:- use_module(library(lists)).

:- dynamic(input_length/1).

%% here(-Tail)//
%
% Capture the current remaining-input suffix as `Tail`, consuming nothing.
% Defined directly as the three-argument DCG body predicate: unifying all three
% positions makes it a non-consuming lookahead that hands back the current
% difference-list state.
here(Tail, Tail, Tail).

%% set_input_length(+Input).
%
% Record the total length of the input list being parsed, so `span_between/3`
% can convert captured suffixes into absolute offsets.  Idempotent across
% parses: the previous value (if any) is retracted first.  Called once by
% `parser.pl` before `phrase/2`.
set_input_length(Input) :-
  length(Input, Length),
  retractall(input_length(_)),
  assertz(input_length(Length)).

%% span_between(+StartTail, +EndTail, -Span).
%
% Turn two captured suffixes (start and end of a construct) into a
% `span(Start, End)` of absolute 0-based character offsets, `End` exclusive.
span_between(StartTail, EndTail, span(Start, End)) :-
  offset(StartTail, Start),
  offset(EndTail, End).

%% zero_width_span_at(+Tail, -Span).
%
% A zero-width `span(Offset, Offset)` at the current position.  Useful for a
% construct that occupies no source text at the point it is recorded (rare; the
% macro stage will use it for fully synthesized nodes that have no real extent).
zero_width_span_at(Tail, span(Offset, Offset)) :-
  offset(Tail, Offset).

%% node_span(+Node, -Span).
%
% Read the `span(Start, End)` off any spanned AST node.  By construction every
% spanned node carries its span as its LAST argument, so this takes the last
% argument and checks it is a `span/2`.  Used where a composite node's span must
% be derived from its children (e.g. `binary.pl` re-associates operator trees
% and a rebuilt `binary_node` should cover its actual left and right operands).
node_span(Node, Span) :-
  Node =.. Arguments,
  append(_, [Last], Arguments),
  Last = span(_, _),
  !,
  Span = Last.

%% span_cover(+Left, +Right, -Span).
%
% The span that covers two already-spanned nodes: from the start of `Left` to
% the end of `Right`.  (Assumes `Left` precedes `Right` in source order.)
span_cover(Left, Right, span(Start, End)) :-
  node_span(Left, span(Start, _)),
  node_span(Right, span(_, End)).

%% offset(+Tail, -Offset).
%
% The absolute 0-based offset of a captured input suffix `Tail`: the total input
% length minus how much input remains.  Exported for the few rules that already
% hold one endpoint as an integer (a child node's recorded start) and need to
% convert the other endpoint, captured with `here//1`, to an offset.
offset(Tail, Offset) :-
  input_length(Total),
  length(Tail, Remaining),
  Offset is Total - Remaining.
