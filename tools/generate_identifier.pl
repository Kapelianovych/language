:- module(generate_identifier, [
  generate_identifier/2,
  main/0
]).

/*  generate_identifier.pl  --  Generate source/parser/identifier.pl from the
    Unicode character database.  (Prolog port of the former
    generate_identifier.py.)

    The `identifier` DCG recognises an identifier as an XID_Start character
    followed by zero or more XID_Continue characters (Unicode UAX #31).  Those
    two properties are defined in the UCD file `DerivedCoreProperties.txt`.

    This script reads that file directly -- from a local path with
    library(pio), or straight from unicode.org with library(http/http_open) --
    extracts the XID_Start and XID_Continue codepoint ranges, merges adjacent
    ones, and emits a Prolog module that tests membership with an O(log n)
    balanced binary search tree.  The tree is stored as id-keyed facts
    `xs_node/xc_node(Id, Lo, Hi, Left, Right)` so Scryer's first-argument
    indexing makes each step O(1); a single giant nested term is avoided
    because Scryer's reader rejects terms past ~500 nested subterms.

    Usage (note Scryer passes script arguments after `--`):

        # from a local copy of the UCD file:
        scryer-prolog tools/generate_identifier.pl -- --ucd DerivedCoreProperties.txt

        # or fetch it from unicode.org (latest, or a pinned version):
        scryer-prolog tools/generate_identifier.pl -- --download
        scryer-prolog tools/generate_identifier.pl -- --download --unicode-version 17.0.0

    By default the result is written to source/parser/identifier.pl; pass
    `--output PATH` (or `-o PATH`) to write elsewhere.
*/

:- use_module(library(pio)).               % phrase_from_file/2, phrase_to_file/2
:- use_module(library(http/http_open)).    % http_open/3
:- use_module(library(error)).             % domain_error/2
:- use_module(library(iso_ext)).           % setup_call_cleanup/3
:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(format)).            % format/2
:- use_module(library(os)).                % argv/1

% ---------------------------------------------------------------------------
% Command line
% ---------------------------------------------------------------------------

latest_url("https://www.unicode.org/Public/UCD/latest/ucd/DerivedCoreProperties.txt").

% Build the URL for a pinned Unicode version, e.g. "17.0.0".
version_url(Version, Url) :-
  append("https://www.unicode.org/Public/", Version, A),
  append(A, "/ucd/DerivedCoreProperties.txt", Url).

%% main.
%
% Entry point when run as a script.  Parses the arguments after `--`, runs the
% generator, and halts.
main :-
  catch(
    ( argv(Args),
      parse_args(Args, Source, Output),
      generate_identifier(Source, Output)
    ),
    Error,
    ( format("error: ~q~n", [Error]), halt(1) )
  ),
  halt(0).

% Defaults mirror the Python version: read a local DerivedCoreProperties.txt
% and write source/parser/identifier.pl, unless overridden.
parse_args(Args, Source, Output) :-
  parse_args(Args,
             file("DerivedCoreProperties.txt"),
             "source/parser/identifier.pl",
             Source, Output).

parse_args([], Source, Output, Source, Output).
parse_args(["--download" | T], _, O0, Source, Output) :-
  latest_url(Url),
  parse_args(T, url(Url), O0, Source, Output).
parse_args(["--unicode-version", V | T], _, O0, Source, Output) :-
  version_url(V, Url),
  parse_args(T, url(Url), O0, Source, Output).
parse_args(["--url", Url | T], _, O0, Source, Output) :-
  parse_args(T, url(Url), O0, Source, Output).
parse_args(["--ucd", Path | T], _, O0, Source, Output) :-
  parse_args(T, file(Path), O0, Source, Output).
parse_args(["--output", Path | T], S0, _, Source, Output) :-
  parse_args(T, S0, Path, Source, Output).
parse_args(["-o", Path | T], S0, _, Source, Output) :-
  parse_args(T, S0, Path, Source, Output).

% ---------------------------------------------------------------------------
% Driver
% ---------------------------------------------------------------------------

%% generate_identifier(+Source, +OutputPath).
%
% Source is `file(Path)` or `url(Url)`.  Reads the UCD data, extracts and
% merges the XID ranges, builds the BSTs, and writes the module.
generate_identifier(Source, OutputPath) :-
  source_chars(Source, Chars),
  parse_ucd(Chars, Version, StartRaw, ContinueRaw),
  ( ( StartRaw == [] ; ContinueRaw == [] ) ->
      domain_error(unicode_xid_data, Source)   % wrong file: no XID ranges
  ; true
  ),
  merge_ranges(StartRaw, StartRanges),
  merge_ranges(ContinueRaw, ContinueRanges),
  build_tree(StartRanges, StartRoot, StartNodes),
  build_tree(ContinueRanges, ContinueRoot, ContinueNodes),
  phrase_to_file(
    file_text(Version, StartNodes, StartRoot, ContinueNodes, ContinueRoot),
    OutputPath
  ),
  report(Version, StartRanges, ContinueRanges, OutputPath).

report(Version, StartRanges, ContinueRanges, OutputPath) :-
  length(StartRanges, StartCount),
  length(ContinueRanges, ContinueCount),
  format("Unicode:      ~s~n", [Version]),
  format("XID_Start:    ~d merged ranges~n", [StartCount]),
  format("XID_Continue: ~d merged ranges~n", [ContinueCount]),
  format("wrote:        ~s~n", [OutputPath]).

% Read the whole source into a character list.  Local files go through
% library(pio); URLs are streamed with http_open/3.
source_chars(file(Path), Chars) :-
  phrase_from_file(all_chars(Chars), Path).
source_chars(url(Url), Chars) :-
  setup_call_cleanup(
    http_open(Url, Stream, []),
    stream_chars(Stream, Chars),
    close(Stream)
  ).

% Match (or emit) an entire list of characters verbatim.
all_chars([]) --> [].
all_chars([C | Cs]) --> [C], all_chars(Cs).

stream_chars(Stream, Chars) :-
  get_char(Stream, C),
  ( C == end_of_file ->
      Chars = []
  ; Chars = [C | Rest],
    stream_chars(Stream, Rest)
  ).

% ---------------------------------------------------------------------------
% Parsing the UCD file
% ---------------------------------------------------------------------------

% Extract the Unicode version (from the header comment) and the raw range
% lists for XID_Start and XID_Continue, line by line.
parse_ucd(Chars, Version, StartRanges, ContinueRanges) :-
  split_lines(Chars, Lines),
  ( member(Line, Lines), phrase(version_line(V), Line, _) ->
      Version = V
  ; Version = "unknown"
  ),
  collect_ranges(Lines, StartRanges, ContinueRanges).

% Split a character list into lines on '\n' (the UCD uses LF line endings).
split_lines(Chars, Lines) :-
  split_lines(Chars, [], Lines).

split_lines([], Acc, [Line]) :-
  reverse(Acc, Line).
split_lines(['\n' | Cs], Acc, [Line | Lines]) :-
  reverse(Acc, Line),
  split_lines(Cs, [], Lines).
split_lines([C | Cs], Acc, Lines) :-
  C \== '\n',
  split_lines(Cs, [C | Acc], Lines).

collect_ranges([], [], []).
collect_ranges([Line | Lines], Starts, Continues) :-
  ( phrase(range_line(Property, Lo, Hi), Line, _) ->
      ( Property == start ->
          Starts = [Lo-Hi | Starts1], Continues = Continues1
      ; Starts = Starts1, Continues = [Lo-Hi | Continues1]
      )
  ; Starts = Starts1, Continues = Continues1
  ),
  collect_ranges(Lines, Starts1, Continues1).

% The version line looks like `# DerivedCoreProperties-17.0.0.txt`.  We grab
% everything after the prefix and strip the `.txt` suffix (the version itself
% contains dots, so we cannot stop at the first one).
version_line(Version) -->
  "# DerivedCoreProperties-",
  all_chars(All),
  { append(Version, ".txt", All) }.

% A data line is `HEX(..HEX)? ; PropertyName # comment`.  We only keep
% XID_Start and XID_Continue; any other line fails to parse and is skipped.
% phrase/3 lets us ignore the trailing ` # comment`.
range_line(Property, Lo, Hi) -->
  hex_number(Lo),
  ( ".." , hex_number(Hi) ; { Hi = Lo } ),
  spaces, ";", spaces,
  property_name(Property).

property_name(start) --> "XID_Start".
property_name(continue) --> "XID_Continue".

spaces --> [C], { space_char(C) }, !, spaces.
spaces --> [].

space_char(' ').
space_char('\t').

hex_number(Number) -->
  hex_digit(D),
  hex_digits(Ds),
  { foldl_hex([D | Ds], 0, Number) }.

hex_digits([D | Ds]) --> hex_digit(D), !, hex_digits(Ds).
hex_digits([]) --> [].

hex_digit(Value) -->
  [C],
  { hex_value(C, Value) }.

hex_value(C, Value) :-
  char_code(C, Code),
  ( Code >= 0'0, Code =< 0'9 -> Value is Code - 0'0
  ; Code >= 0'A, Code =< 0'F -> Value is Code - 0'A + 10
  ; Code >= 0'a, Code =< 0'f -> Value is Code - 0'a + 10
  ).

foldl_hex([], Acc, Acc).
foldl_hex([D | Ds], Acc, Number) :-
  Acc1 is Acc * 16 + D,
  foldl_hex(Ds, Acc1, Number).

% ---------------------------------------------------------------------------
% Merging ranges
% ---------------------------------------------------------------------------

% Sort and coalesce overlapping or adjacent ranges.  sort/2 orders the
% `Lo-Hi` pairs by Lo then Hi (standard term order) and drops exact
% duplicates, which is harmless since any duplicate would coalesce anyway.
merge_ranges(Ranges, Merged) :-
  sort(Ranges, Sorted),
  ( Sorted = [First | Rest] ->
      merge_sorted(Rest, First, Merged)
  ; Merged = []
  ).

merge_sorted([], Current, [Current]).
merge_sorted([Lo-Hi | Rest], CurLo-CurHi, Merged) :-
  ( Lo =< CurHi + 1 ->
      NewHi is max(CurHi, Hi),
      merge_sorted(Rest, CurLo-NewHi, Merged)
  ; Merged = [CurLo-CurHi | Merged1],
    merge_sorted(Rest, Lo-Hi, Merged1)
  ).

% ---------------------------------------------------------------------------
% Building the balanced BST as id-keyed facts
% ---------------------------------------------------------------------------

% A node is nd(Id, Lo, Hi, LeftRef, RightRef); a child reference is either a
% node id or the atom `nil`.  Ids are assigned in pre-order (root first) and
% the node list comes out in post-order, matching the reference generator so
% the output is reproducible.
build_tree(Ranges, Root, Nodes) :-
  build_nodes(Ranges, 0, _, Root, Nodes, []).

build_nodes([], Id, Id, nil, Nodes, Nodes).
build_nodes(Ranges, Id0, Id, MyId, Nodes0, Nodes) :-
  Ranges = [_ | _],
  length(Ranges, N),
  Mid is N // 2,
  length(Left, Mid),
  append(Left, [Lo-Hi | Right], Ranges),
  MyId = Id0,
  Id1 is Id0 + 1,
  build_nodes(Left, Id1, Id2, LeftRef, Nodes0, Nodes1),
  build_nodes(Right, Id2, Id, RightRef, Nodes1, Nodes2),
  Nodes2 = [nd(MyId, Lo, Hi, LeftRef, RightRef) | Nodes].

% ---------------------------------------------------------------------------
% Emitting the module
% ---------------------------------------------------------------------------

file_text(Version, StartNodes, StartRoot, ContinueNodes, ContinueRoot) -->
  header(Version),
  "\n",
  "xs_root(", integer(StartRoot), ").\n",
  "xc_root(", integer(ContinueRoot), ").\n",
  "\n",
  "% XID_Start ranges.\n",
  facts(xs_node, StartNodes),
  "\n",
  "% XID_Continue ranges.\n",
  facts(xc_node, ContinueNodes).

% The fixed preamble: the identifier DCG and the membership lookup.  Only the
% Unicode-version line varies.
header(Version) -->
  ":- module(identifier, [identifier//1]).\n",
  "\n",
  ":- use_module(library(dcgs)).\n",
  "\n",
  "% GENERATED FILE -- do not edit by hand.\n",
  "% Regenerate with: scryer-prolog tools/generate_identifier.pl -- --download\n",
  "% Source: Unicode ", all_chars(Version), " DerivedCoreProperties.txt (XID_Start / XID_Continue).\n",
  "%\n",
  "% An identifier is an XID_Start character followed by zero or more\n",
  "% XID_Continue characters (Unicode UAX #31).\n",
  "identifier(identifier_node([FirstCharacter | RestCharacters])) -->\n",
  "  identifier_first_character(FirstCharacter),\n",
  "  identifier_rest_characters(RestCharacters).\n",
  "\n",
  "identifier_first_character(Character) -->\n",
  "  [Character],\n",
  "  { char_code(Character, Code), xid_start(Code) }.\n",
  "\n",
  "identifier_rest_characters([ContinueCharacter | Characters]) -->\n",
  "  identifier_continue_character(ContinueCharacter),\n",
  "  identifier_rest_characters(Characters).\n",
  "% The default clause has to be the last definition to enforce Prolog\n",
  "% to report the largest available token as identifier first.\n",
  "identifier_rest_characters([]) --> [].\n",
  "\n",
  "identifier_continue_character(Character) -->\n",
  "  [Character],\n",
  "  { char_code(Character, Code), xid_continue(Code) }.\n",
  "\n",
  "% Membership of a codepoint in a property's range set, via an O(log n)\n",
  "% balanced binary search tree.  The tree is stored as id-keyed facts\n",
  "% `xs_node/xc_node(Id, Lo, Hi, Left, Right)`: the node covers the inclusive\n",
  "% range Lo..Hi, with smaller codepoints in the Left subtree and larger in\n",
  "% Right.  A child of `nil` is absent, so its lookup simply fails.  First-\n",
  "% argument indexing on Id makes each step O(1), the whole search O(log n).\n",
  "xid_start(Code) :- xs_root(Root), in_start(Root, Code).\n",
  "xid_continue(Code) :- xc_root(Root), in_continue(Root, Code).\n",
  "\n",
  "in_start(Id, Code) :-\n",
  "  xs_node(Id, Lo, Hi, Left, Right),\n",
  "  ( Code < Lo -> in_start(Left, Code)\n",
  "  ; Code > Hi -> in_start(Right, Code)\n",
  "  ; true\n",
  "  ).\n",
  "\n",
  "in_continue(Id, Code) :-\n",
  "  xc_node(Id, Lo, Hi, Left, Right),\n",
  "  ( Code < Lo -> in_continue(Left, Code)\n",
  "  ; Code > Hi -> in_continue(Right, Code)\n",
  "  ; true\n",
  "  ).\n".

% Emit `Functor(Id,0xLO,0xHI,LeftRef,RightRef).` for each node, one per line.
facts(_, []) --> [].
facts(Functor, [nd(Id, Lo, Hi, LeftRef, RightRef) | Nodes]) -->
  functor_name(Functor),
  "(", integer(Id),
  ",", hex(Lo),
  ",", hex(Hi),
  ",", reference(LeftRef),
  ",", reference(RightRef),
  ").\n",
  facts(Functor, Nodes).

functor_name(Functor) -->
  { atom_chars(Functor, Chars) },
  all_chars(Chars).

reference(nil) --> "nil".
reference(Id) --> { integer(Id) }, integer(Id).

integer(Number) -->
  { number_chars(Number, Chars) },
  all_chars(Chars).

% A codepoint as `0x` + uppercase hex, zero-padded to at least four digits
% (matching the reference generator's `0x{:04X}` formatting).
hex(Number) -->
  "0x",
  { hex_chars(Number, Chars) },
  all_chars(Chars).

hex_chars(Number, Padded) :-
  hex_digit_chars(Number, Chars),
  length(Chars, Length),
  ( Length < 4 ->
      PadCount is 4 - Length,
      length(Zeros, PadCount),
      maplist(=('0'), Zeros),
      append(Zeros, Chars, Padded)
  ; Padded = Chars
  ).

hex_digit_chars(0, ['0']) :- !.
hex_digit_chars(Number, Chars) :-
  Number > 0,
  hex_digit_chars_rev(Number, Reversed),
  reverse(Reversed, Chars).

hex_digit_chars_rev(0, []) :- !.
hex_digit_chars_rev(Number, [Char | Chars]) :-
  Number > 0,
  Digit is Number mod 16,
  hex_digit_char(Digit, Char),
  Rest is Number // 16,
  hex_digit_chars_rev(Rest, Chars).

hex_digit_char(Value, Char) :-
  ( Value < 10 -> Code is 0'0 + Value ; Code is 0'A + Value - 10 ),
  char_code(Char, Code).

:- initialization(main).
