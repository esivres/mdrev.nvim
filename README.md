# mdrev.nvim

[mdrev](https://github.com/esivres/mdrev) review comments for markdown
documents, natively in Neovim: in-text underlines from the language server,
a compose float for new comments, a thread float for whole discussions.

The `.md` itself never changes — comments live in a `doc.md.review.yaml`
sidecar next to it, owned by mdrev. This plugin is a front end, the way the
Zed extension is; the terminal UI (`mdrev threads`) keeps working alongside.

Requires Neovim ≥ 0.11 and the `mdrev` binary on `$PATH`
(`brew install esivres/mdrev/mdrev` or `go install github.com/esivres/mdrev/cmd/mdrev@latest`).

## Install

```lua
-- lazy.nvim
{
	"esivres/mdrev.nvim",
	opts = {},
}
```

`setup` declares the language server (`lsp/mdrev.lua`, enabled via
`vim.lsp.enable`) and buffer-local keys for markdown. Both are optional:

```lua
opts = {
	cmd = "mdrev",          -- binary to call
	lsp = true,             -- false to configure the language server yourself
	keys = {                -- set to false to use :MdrevComment / :MdrevThreads only
		comment = "mc",     -- a visual selection, or the line under the cursor
		threads = "mt",     -- on the line the cursor is on
	},
}
```

## What you get

- **Underlines** — the language server anchors every open comment to its
  quoted fragment and re-anchors as the document changes; a vanished
  fragment is kept and marked `[anchor lost]`.
- **`mc` on a selection** — a compose float; `:w` files the comment
  (`:q` discards). A multi-line selection anchors to the whole fragment.
- **`mc` with no selection** — comments the line under the cursor; mdrev
  anchors on the line's first words.
- **`mt` near a comment** — a thread float: the paragraph the comment is
  about with the anchored fragment marked, the discussion, `r` reply,
  `x` resolve, `j`/`k` other threads, `q` close.
- **Everything stays in sync** — actions go through the mdrev CLI against
  the sidecar; the language server picks changes up within a second, and
  lock contention with it is retried once.

## Verify the install

```sh
scripts/smoke.sh
```

runs the flows headless against a throwaway fixture.

## License

MIT
