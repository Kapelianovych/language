:- module(serve, []).

/*  lsp/serve.pl  --  Entry point for running the server as a process.

    `lsp.pl` is a plain library (exports `serve/0` / `serve_streams/2`) with no
    side effects on load, same as `cli.pl`'s relationship to `compiler.pl`.
    This file is the other half: load it directly and it starts the JSON-RPC
    loop over stdin/stdout immediately, so an LSP client just execs
    `scryer-prolog lsp/serve.pl` (or `bin/sl-lsp`) with no further ceremony.
*/

:- use_module('lsp', [serve/0]).

% `serve/0` returns once its input stream hits end-of-file (the normal `exit`
% notification instead calls `halt` directly, from inside `lsp.pl`). Without an
% explicit `halt` here, falling off the end of the loaded file drops into
% Scryer's interactive top-level -- on a closed stdin that then errors instead
% of exiting, which is the wrong failure mode for a process an editor manages.
:- initialization((serve, halt)).
