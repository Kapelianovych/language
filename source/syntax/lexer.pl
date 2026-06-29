:- module(lexer, [tokenize/2, tokens_text/2]).

/*  source/syntax/lexer.pl  --  Lossless tokenizer for the LSP front-end.
    ========================================================================

    WHY A NEW SUBSYSTEM (`source/syntax/`)

      The batch compiler's parser (`source/parser/`) is a scannerless,
      backtracking DCG: great for a one-shot compile, but for an editor we need
      three different properties -- ERROR RECOVERY (keep a usable tree for
      broken code), a LOSSLESS tree (every byte represented, for formatting /
      incremental reuse), and INCREMENTALITY.  Those are engineering properties
      of the parser's *shape*, not of the grammar, so we build a separate
      front-end here and leave the compiler untouched.

      The pipeline is the classic editor-grade shape:

          source text
            |  tokenize/2          (THIS FILE)   -> flat list of lossless tokens
            v
          recovering recursive-descent parser    -> lossless green tree + diags
            v
          demand-driven query engine             -> incremental name/type checks

    WHAT "LOSSLESS" MEANS HERE

      `tokenize/2` turns the source into a FLAT list of tokens that covers the
      input with NO gaps and NO overlaps: whitespace and comments are emitted as
      ordinary ("trivia") tokens rather than skipped.  The invariant, checked by
      `tokens_text/2` in the tests, is:

          concatenation of every token's Text  ==  the original source

      That invariant is what lets the tree built on top reproduce the file
      exactly (for formatting, and so an edit can be mapped back to bytes).

    TOKEN SHAPE

          t(Kind, Text, Start, End)

      Text  : the exact characters of the lexeme, as a cons list of char atoms
              (so concatenation reconstructs the source verbatim).
      Start : 0-based character offset of the first character.
      End   : 0-based offset one past the last character (half-open, like spans
              in `source/parser/position.pl`, so End-Start = length).

      Kind is one of:
        whitespace | comment            -- trivia (lossless, ignored for syntax)
        number | string | ident         -- literals / names
        eof                             -- the single terminator (empty Text)
        unknown                         -- a character no rule recognises
        <operator-atom>                 -- e.g. '+', '->', '==', '(', '{', '.'
                                           (the lexeme itself, as an atom, so the
                                           parser can match on Kind directly)

    FAITHFULNESS BY REUSE

      Rather than re-encode the language's lexical rules (and risk drifting from
      the real compiler), we REUSE the existing predicates:
        * Unicode identifier classes  -- `xid_start/1`, `xid_continue/1`
        * Unicode whitespace / newline -- `is_whitespace/1`, `is_new_line/1`
        * the full numeric grammar     -- `number_literal//1` (4 bases, digit
          grouping with `,`, float, scientific).  We run it only to find the
          EXTENT of a number; its produced AST node is discarded here.

    STRINGS ARE SCANNED, NOT PRE-SPLIT

      The language is scannerless precisely because a string can interpolate an
      expression -- `'a {f(x)} b'` -- and that expression can contain more
      strings.  We honour that with mutually-recursive scanners (`scan_string`
      / `scan_interpolation`) that track brace depth AND recurse into nested
      strings, so the matching closing quote is always found correctly.  The
      whole literal becomes ONE `string` token (its internal parts are parsed
      later, by the parser, from the token's raw Text).
*/

% The existing lexical helpers (and the operator literals below) are written as
% double-quoted char lists, so this module reads "ab" as [a,b].
:- set_prolog_flag(double_quotes, chars).

:- use_module(library(lists)).
:- use_module('../unicode', [xid_start/1, xid_continue/1]).
:- use_module('../parser/whitespace', [is_whitespace/1, is_new_line/1]).

% ---------------------------------------------------------------------------
% Entry point.
% ---------------------------------------------------------------------------

%% tokenize(+Chars, -Tokens).
%
% `Chars` is the whole source as a list of character atoms.  `Tokens` is the
% lossless token list ending in exactly one `t(eof, [], N, N)`.
tokenize(Chars, Tokens) :-
  lex(Chars, 0, Tokens).

% lex(+Chars, +Offset, -Tokens): pull one token off the front, advance the
% offset by its length, repeat.  Each step consumes >= 1 character (or stops at
% end of input), so it always terminates.
lex([], Offset, [t(eof, [], Offset, Offset)]).
lex([C | Cs], Offset, [Token | Tokens]) :-
  next_token([C | Cs], Offset, Token, Rest, NextOffset),
  lex(Rest, NextOffset, Tokens).

% ---------------------------------------------------------------------------
% One token.  The clauses are ordered by priority; the FIRST that matches the
% current prefix wins (maximal-munch is handled inside each scanner and, for
% operators, by ordering the operator table longest-first).
% ---------------------------------------------------------------------------

next_token(Chars, Offset, t(Kind, Text, Offset, End), Rest, End) :-
  ( Chars = [C | _], is_whitespace(C) ->
      take_while(whitespace_char, Chars, Text, Rest), Kind = whitespace
  ; Chars = ['#' | _] ->
      scan_comment(Chars, Text, Rest), Kind = comment
  ; Chars = ['\'' | _] ->
      scan_string(Chars, Text, Rest), Kind = string
  ; Chars = [C | _], decimal_digit(C) ->
      scan_number(Chars, Text, Rest), Kind = number
  ; Chars = [C | _], char_code(C, Code), xid_start(Code) ->
      scan_ident(Chars, Text, Rest), Kind = ident
  ; Chars = ['_' | Cs1] ->
      % `_` is not an XID_Start character, so it is its own token: the wildcard
      % pattern and the call-argument placeholder, both unambiguous for that reason.
      Text = ['_'], Rest = Cs1, Kind = underscore
  ; lex_operator(Chars, Text, Rest) ->
      atom_chars(Kind, Text)            % Kind IS the operator, e.g. '->', '('
  ; Chars = [C | Cs1] ->
      Text = [C], Rest = Cs1, Kind = unknown
  ),
  length(Text, Length),
  End is Offset + Length.

% ---------------------------------------------------------------------------
% Character-class helpers (thin wrappers so they can be passed to take_while/4).
% ---------------------------------------------------------------------------

whitespace_char(C) :- is_whitespace(C).
decimal_digit(C)   :- C @>= '0', C @=< '9'.
xid_continue_char(C) :- char_code(C, Code), xid_continue(Code).
not_newline(C)     :- \+ is_new_line(C).

% take_while(+Pred, +Chars, -Taken, -Rest): greedily take the leading run of
% characters satisfying Pred.  The cut commits to the longest run (there is
% never a reason to take fewer trivia/identifier characters).
take_while(Pred, [C | Cs], [C | Taken], Rest) :-
  call(Pred, C), !,
  take_while(Pred, Cs, Taken, Rest).
take_while(_Pred, Rest, [], Rest).

% ---------------------------------------------------------------------------
% Comments:  `#` to (but not including) the end of the line.  The trailing
% newline is left for the following whitespace token, which keeps both tokens'
% Text exact and the concatenation lossless.
% ---------------------------------------------------------------------------

scan_comment(['#' | Cs], ['#' | Text], Rest) :-
  take_while(not_newline, Cs, Text, Rest).

% ---------------------------------------------------------------------------
% Identifiers:  one XID_Start then a run of XID_Continue (UAX #31), exactly as
% `source/parser/identifier.pl`.  The first character is already known to be
% XID_Start from the caller's guard.
% ---------------------------------------------------------------------------

scan_ident([C | Cs], [C | Text], Rest) :-
  take_while(xid_continue_char, Cs, Text, Rest).

% ---------------------------------------------------------------------------
% Numbers.  This MUST be deterministic and longest-match.  The old grammar's
% alternation is ordered `binary | octal | decimal | hexadecimal` and relies on
% the full-consumption parse backtracking out of a wrong reading -- e.g. for
% `0xFF` it first reads decimal `0`, and only backtracks to hexadecimal because
% `0` followed by `xFF` fails to parse the rest of the file.  A lexer has no
% such downstream signal, so we instead dispatch on the BASE PREFIX explicitly
% and only treat `0x`/`0o`/`0b` as a base when a matching digit actually
% follows (otherwise the `0` is a plain decimal and the letter starts an
% identifier).  Digit grouping with `,` (e.g. `1,000`) is supported in every
% base, matching `source/parser/number_literal.pl`.
% ---------------------------------------------------------------------------

scan_number(['0', P | Cs], ['0', P | Digits], Rest) :-
  base_prefix(P, DigitClass),
  Cs = [D | _], call(DigitClass, D),          % a real base literal needs >=1 digit
  !,
  digit_run(DigitClass, Cs, Digits, Rest).
scan_number(Chars, Text, Rest) :-
  scan_decimal(Chars, Text, Rest).

base_prefix(x,   hexadecimal_digit).
base_prefix('X', hexadecimal_digit).
base_prefix(o,   octal_digit).
base_prefix('O', octal_digit).
base_prefix(b,   binary_digit).
base_prefix('B', binary_digit).

binary_digit(C)      :- member(C, ['0', '1']).
octal_digit(C)       :- C @>= '0', C @=< '7'.
hexadecimal_digit(C) :- decimal_digit(C) ; member(C, [a,b,c,d,e,f,'A','B','C','D','E','F']).

% A decimal literal: integer part, then an optional `.fraction`, then an
% optional `e`/`E` exponent.  Fraction and exponent are only consumed when
% genuinely present (a `.` not followed by a digit is member access; an `e` not
% followed by digits is the start of an identifier), so the scanner never grabs
% characters that are not part of the number.
scan_decimal(Chars, Text, Rest) :-
  digit_run(decimal_digit, Chars, IntPart, R1),
  optional_fraction(R1, FracPart, R2),
  optional_exponent(R2, ExpPart, Rest),
  append(IntPart, FracPart, T1),
  append(T1, ExpPart, Text).

optional_fraction(['.', D | Cs], ['.' | Frac], Rest) :-
  decimal_digit(D), !,
  digit_run(decimal_digit, [D | Cs], Frac, Rest).
optional_fraction(Rest, [], Rest).

optional_exponent([E | Cs], Exp, Rest) :-
  ( E == e ; E == 'E' ),
  exponent_digits(Cs, Tail, Rest0),
  !,
  Exp = [E | Tail], Rest = Rest0.
optional_exponent(Rest, [], Rest).

exponent_digits(Cs, Tail, Rest) :-
  optional_sign(Cs, Sign, Cs1),
  Cs1 = [D | _], decimal_digit(D),
  digit_run(decimal_digit, Cs1, Digits, Rest),
  append(Sign, Digits, Tail).

% NOTE: the sign characters are compared as `(+)` / `(-)`, not `'+'` / `'-'`.
% Scryer's reader rejects a quoted operator atom as the right operand of `==`
% (`X == '+'` raises a `syntax_error(incomplete_reduction)`); wrapping the
% operator in parentheses reads it as a plain atom operand.
optional_sign([S | Cs], [S], Cs) :- ( S == (+) ; S == (-) ), !.
optional_sign(Rest, [], Rest).

% A run of base-`DigitClass` digits, allowing a single `,` BETWEEN digits as a
% grouping separator (never trailing).  The first digit is guaranteed present by
% the caller.
digit_run(DigitClass, [C | Cs], [C | Run], Rest) :-
  call(DigitClass, C), !,
  digit_run_tail(DigitClass, Cs, Run, Rest).

digit_run_tail(DigitClass, [',', C | Cs], [',', C | Run], Rest) :-
  call(DigitClass, C), !,
  digit_run_tail(DigitClass, Cs, Run, Rest).
digit_run_tail(DigitClass, [C | Cs], [C | Run], Rest) :-
  call(DigitClass, C), !,
  digit_run_tail(DigitClass, Cs, Run, Rest).
digit_run_tail(_DigitClass, Rest, [], Rest).

% ---------------------------------------------------------------------------
% Strings:  a single-quoted literal, scanned WHOLE (interpolation included) so
% it becomes one token.  Handles:
%   \\  \'  \{   -- escapes (backslash + the next char are taken verbatim)
%   { ... }      -- interpolation: balanced braces, recursing into nested
%                   strings so an inner quote never closes the outer string
%   end of input -- treated as an unterminated string (lossless: take what is
%                   there; the parser reports the missing quote)
% scan_string consumes the OPENING quote then delegates to scan_string_body.
% ---------------------------------------------------------------------------

scan_string(['\'' | Cs], ['\'' | Text], Rest) :-
  scan_string_body(Cs, Text, Rest).

scan_string_body([], [], []).                                  % unterminated
scan_string_body(['\\', X | Cs], ['\\', X | Text], Rest) :- !, % escape pair
  scan_string_body(Cs, Text, Rest).
scan_string_body(['\'' | Cs], ['\''], Cs) :- !.                % closing quote
scan_string_body(['{' | Cs], ['{' | Text], Rest) :- !,         % interpolation
  scan_interpolation(Cs, Inner, Cs1),
  scan_string_body(Cs1, Tail, Rest),
  append(Inner, Tail, Text).
scan_string_body([C | Cs], [C | Text], Rest) :-                % ordinary char
  scan_string_body(Cs, Text, Rest).

% scan_interpolation: consume up to and INCLUDING the matching `}`.  Nested `{`
% recurse (brace depth) and a `'` recurses into a nested string, so quotes and
% braces inside an interpolation can never fool the outer scan.
scan_interpolation([], [], []).                                % unterminated
scan_interpolation(['}' | Cs], ['}'], Cs) :- !.                % matching close
scan_interpolation(['{' | Cs], Out, Rest) :- !,                % nested braces
  scan_interpolation(Cs, Inner, Cs1),
  scan_interpolation(Cs1, Tail, Rest),
  append(['{' | Inner], Tail, Out).
scan_interpolation(['\'' | Cs], Out, Rest) :- !,               % nested string
  scan_string_body(Cs, Str, Cs1),
  scan_interpolation(Cs1, Tail, Rest),
  append(['\'' | Str], Tail, Out).
scan_interpolation([C | Cs], [C | Out], Rest) :-               % ordinary char
  scan_interpolation(Cs, Out, Rest).

% ---------------------------------------------------------------------------
% Operators and punctuation, matched by MAXIMAL MUNCH: the table is ordered so
% every multi-character operator appears before any operator that is a prefix of
% it (e.g. "->" before "-", "==" before "="), and the first match wins.  This is
% the lexer's only place where token boundaries depend on lookahead.
% ---------------------------------------------------------------------------

operators([
  % two-character (must precede their one-character prefixes)
  "<<", ">>", "&&", "^^", "||", "<=", ">=", "==", "!=", "->", "=>",
  % one-character operators
  "*", "/", "+", "-", "<", ">", "&", "^", "|", "!", "~",
  % punctuation / structural
  "=", ":", ".", ",", "@", "`", "(", ")", "{", "}"
]).

lex_operator(Chars, Op, Rest) :-
  operators(Operators),
  member(Op, Operators),
  append(Op, Rest, Chars),
  !.

% ---------------------------------------------------------------------------
% Losslessness check helper: concatenate every token's Text back into a single
% character list.  The tests assert this equals the original source.
% ---------------------------------------------------------------------------

tokens_text([], []).
tokens_text([t(_Kind, Text, _S, _E) | Tokens], All) :-
  tokens_text(Tokens, Rest),
  append(Text, Rest, All).
