-- mdrev: review comments for markdown documents, in the editor.
--
-- Two layers over one store, as the Zed extension arranges it:
--   * the language server (declared in lsp/mdrev.lua) for in-text
--     underlines and code actions;
--   * this plugin for what an LSP client cannot show: a compose float for
--     new comments, a thread float for whole discussions.
--
-- The terminal UI (`mdrev threads`) stays available; this is another front
-- end, not a replacement.
local M = {}

function M.setup(opts)
	opts = opts or {}
	local cli = require("mdrev.cli")
	cli.setup(opts)

	if opts.lsp ~= false then
		if cli.bin() ~= "mdrev" then
			-- An overridden binary must reach the language server too, or
			-- the underlines silently never appear.
			vim.lsp.config.mdrev = vim.tbl_extend("force", vim.lsp.config.mdrev or {},
				{ cmd = { cli.bin(), "lsp" } })
		end
		vim.lsp.enable("mdrev") -- config comes from lsp/mdrev.lua on the runtimepath
	end

	local keys = opts.keys or { comment = "mc", threads = "mt" }
	local group = vim.api.nvim_create_augroup("mdrev", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "markdown",
		callback = function(args)
			if keys.comment then
				vim.keymap.set("x", keys.comment, function()
					-- Visual mappings run with the selection still active:
					-- '< and '> hold the previous one, v and . the live one.
					local a, b = vim.fn.line("v"), vim.fn.line(".")
					require("mdrev.comment").comment(args.buf,
						math.min(a, b) - 1, math.max(a, b) - 1)
				end, { buffer = args.buf, desc = "mdrev: comment the selection" })
				vim.keymap.set("n", keys.comment, function()
					require("mdrev.comment").line(args.buf, vim.fn.line(".") - 1)
				end, { buffer = args.buf, desc = "mdrev: comment the line" })
			end
			if keys.threads then
				vim.keymap.set("n", keys.threads, function()
					require("mdrev.threads").open(args.buf)
				end, { buffer = args.buf, desc = "mdrev: threads near the cursor" })
			end
		end,
	})
end

return M
