:- module(mutability, [mutability//1]).

/*  mutability.pl  --  The optional `mutable` prefix shared by tuple members
    (in values) and tuple-type members (in types).

    Produces `mutable` when the keyword is present, `readonly` otherwise.
    `mutable` is a *soft* keyword: the mandatory trailing separator means a
    bare identifier `mutable` (not followed by a member) is still an
    ordinary name.
*/

:- use_module(library(dcgs)).
:- use_module(separator, [
  separator//0,
  separators//0
]).

mutability(mutable) -->
  "mutable",
  separator, % mandatory: distinguishes the keyword from an identifier
  separators.
mutability(readonly) --> [].
