:- module(roundtrip, [roundtrip_results/1]).

% Lossless round-trip property tests for the lexer and parser.  These hold for
% ANY input -- including comments, trailing whitespace, Unicode identifiers and
% even syntactically malformed programs -- because the front-end is lossless and
% the parser recovers rather than dropping text:
%
%   * lexer:  tokens_text(tokenize(S))          == S
%   * parser: green_text(parse_tokens(tokenize(S))) == S
%
% Run over every `*.sl` in test/fixtures/golden AND test/fixtures/roundtrip, so
% the golden programs double as round-trip inputs and test/fixtures/roundtrip
% holds the tricky-but-not-necessarily-compilable cases.

:- use_module(library(lists)).
:- use_module(test_harness, [read_file_chars/2, sl_fixtures/2]).
:- use_module('../source/syntax/lexer',  [tokenize/2, tokens_text/2]).
:- use_module('../source/syntax/parser', [parse_tokens/3, green_text/2]).

roundtrip_dir("test/fixtures/golden").
roundtrip_dir("test/fixtures/roundtrip").

% roundtrip_results(-Results).
roundtrip_results(Results) :-
  findall(Dir-Name,
          ( roundtrip_dir(Dir), sl_fixtures(Dir, Names), member(Name, Names) ),
          Fixtures),
  maplist(roundtrip_one, Fixtures, Results).

roundtrip_one(Dir-SlName, result(NameAtom, Status)) :-
  append(Dir, ['/' | SlName], PathChars),
  atom_chars(NameAtom, PathChars),
  ( read_file_chars(PathChars, Source) ->
      catch(roundtrip_status(Source, Status), Error, Status = fail(threw(Error)))
  ;   Status = fail(cannot_read_source)
  ).

% Lexer first; only check the parser once the lexer is lossless (the parser is
% fed the lexer's tokens, so a lexer failure would be reported twice otherwise).
roundtrip_status(Source, Status) :-
  ( lexer_roundtrip(Source) ->
      ( parser_roundtrip(Source) -> Status = pass
      ; Status = fail(parser_roundtrip_mismatch) )
  ; Status = fail(lexer_roundtrip_mismatch)
  ).

lexer_roundtrip(Source) :-
  tokenize(Source, Tokens),
  tokens_text(Tokens, Back),
  Back == Source.

parser_roundtrip(Source) :-
  tokenize(Source, Tokens),
  parse_tokens(Tokens, GreenTree, _Diagnostics),
  green_text(GreenTree, Back),
  Back == Source.
