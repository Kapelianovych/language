:- module(module_paths, [
  read_source_chars/2,
  force_char_list/2,
  canonical_chars/2,
  normalise_path/2,
  module_directory/2,
  resolve_source_path/3,
  source_to_js_path/2
]).

/*  module_paths.pl  --  Shared module-path arithmetic and source reading.

    These helpers are used by BOTH the batch build driver (`module_loader.pl`)
    and the incremental analysis engine (`syntax/queries.pl`), so they live in
    one place: a module path means the same thing, and a name read from disk has
    the same representation, in both pipelines.  Keeping them here also keeps the
    incremental engine free of the code generator (which `module_loader` pulls
    in but the editor front-end does not need).

    A MODULE is identified by its normalised source path (a character list).
    `use ./math` in `Dir/a.sl` refers to module `Dir/math.sl`; the emitted JS
    imports from `"./math.js"` (the relative specifier, extension swapped).
*/

:- use_module(library(pio)).
:- use_module(library(dcgs)).
:- use_module(library(lists)).

% read_source_chars(+Path, -Chars).  Read a source file as a canonical cons list
% of character atoms.  FAILS (does not throw) if the file cannot be read, so each
% caller chooses how to report a missing module.
read_source_chars(Path, Chars) :-
  catch(phrase_from_file(all_chars(RawSource), Path), _, fail),
  % `phrase_from_file` yields a partial-string-backed list; force a plain cons
  % list of character atoms so that names built later by appending (qualified
  % module names) share one representation with names read by the parser.
  % Otherwise equal-looking names can differ as `assoc` keys (their `compare/3`
  % order is representation-sensitive) and qualified lookups silently miss.
  force_char_list(RawSource, Chars).

force_char_list([], []).
force_char_list([Character | Characters], [Character | Forced]) :-
  force_char_list(Characters, Forced).

% Force a canonical cons-list representation: `append/3` can leave a partial
% string tail, and `library(assoc)` compares partial strings and plain cons
% lists as DIFFERENT keys -- mixing the two corrupts an AVL once it holds 3+
% modules (a present key then silently misses).
canonical_chars([], []).
canonical_chars([Character | Characters], [Character | Rest]) :-
  canonical_chars(Characters, Rest).

% ---------------------------------------------------------------------------
% Paths
% ---------------------------------------------------------------------------

% The dependency's source path: the importer's directory joined with the
% relative `use` path, with a `.sl` extension, normalised.
resolve_source_path(Directory, RelativePath, SourcePath) :-
  append(Directory, "/", DirectorySlash),
  append(DirectorySlash, RelativePath, Joined),
  append(Joined, ".sl", WithExtension),
  normalise_path(WithExtension, SourcePath).

source_to_js_path(SourcePath, JsPath) :-
  ( append(Prefix, ".sl", SourcePath) ->
      append(Prefix, ".js", JsPath)
  ; JsPath = SourcePath
  ).

% Everything up to (not including) the last `/`; `.` when there is none.
module_directory(Path, Directory) :-
  reverse(Path, Reversed),
  ( append(_FileReversed, ['/' | DirectoryReversed], Reversed) ->
      reverse(DirectoryReversed, Directory)
  ; Directory = ['.']
  ).

% Resolve `.` and `..` segments.
normalise_path(Path, Normalised) :-
  split_on_slash(Path, Segments),
  resolve_segments(Segments, [], ResolvedReversed),
  reverse(ResolvedReversed, Resolved),
  join_on_slash(Resolved, Joined),
  canonical_chars(Joined, Normalised).

split_on_slash(Chars, [Segment | Segments]) :-
  append(Segment, ['/' | Rest], Chars), !,
  split_on_slash(Rest, Segments).
split_on_slash(Chars, [Chars]).

resolve_segments([], Accumulator, Accumulator).
resolve_segments([Segment | Rest], Accumulator, Out) :-
  ( Segment = ['.'] ->
      Accumulator1 = Accumulator
  ; Segment = ['.', '.'] ->
      ( Accumulator = [Top | AccumulatorRest], Top \= ['.', '.'], Top \= [] ->
          Accumulator1 = AccumulatorRest
      ; Accumulator1 = [Segment | Accumulator]
      )
  ; Accumulator1 = [Segment | Accumulator]
  ),
  resolve_segments(Rest, Accumulator1, Out).

join_on_slash([], []).
join_on_slash([Segment], Segment) :- !.
join_on_slash([Segment | Segments], Joined) :-
  join_on_slash(Segments, Rest),
  append(Segment, ['/' | Rest], Joined).

% Match (or emit) an entire list of characters verbatim.
all_chars([]) --> [].
all_chars([Character | Characters]) -->
  [Character],
  all_chars(Characters).
