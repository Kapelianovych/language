use zed_extension_api as zed;

struct SilentExtension;

impl zed::Extension for SilentExtension {
    fn new() -> Self {
        SilentExtension
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> zed::Result<zed::Command> {
        // The server is `bin/sl-lsp` from the language's own repository (a
        // shell wrapper around `scryer-prolog lsp/serve.pl`, not a
        // standalone binary this extension can download), so it must
        // already be on PATH -- same expectation as `bin/slc` for the
        // compiler.
        let path = worktree.which("sl-lsp").ok_or_else(|| {
            "sl-lsp not found on PATH. Add this repository's bin/ directory to PATH.".to_string()
        })?;

        Ok(zed::Command {
            command: path,
            args: Vec::new(),
            env: Default::default(),
        })
    }
}

zed::register_extension!(SilentExtension);
