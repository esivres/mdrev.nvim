-- Headless runtime for the smoke: plugin on the runtimepath. MDREV_LSP=0
-- keeps the language server off for the flow run, where it would only add
-- async noise; without it the full setup runs, as lazy.nvim would.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
require("mdrev").setup({ lsp = os.getenv("MDREV_LSP") ~= "0" })
