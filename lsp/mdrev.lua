-- The language server, as Neovim 0.11+ picks it up from the runtimepath.
return {
	cmd = { "mdrev", "lsp" },
	filetypes = { "markdown" },
	root_markers = { ".git" },
}
