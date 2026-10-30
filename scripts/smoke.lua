-- Headless end-to-end smoke of the plugin's three flows, against a real
-- mdrev binary and a throwaway fixture: a multi-line comment must be marked
-- as ONE fragment across both of its lines, then replied to, then resolved.
local doc = vim.fn.argv(0)
local docbuf = vim.api.nvim_get_current_buf()
local threads = require("mdrev.threads")
local failed = {}

local function check(name, cond, detail)
	if cond then
		print(("ok   %s"):format(name))
	else
		print(("FAIL %s%s"):format(name, detail and (": " .. detail) or ""))
		failed[#failed + 1] = name
	end
end

local function sync_list()
	local out = vim.system({ "mdrev", "list", doc, "--json" }, { text = true }):wait().stdout or "[]"
	return vim.json.decode(out)
end

local function wait_for(name, fn)
	local ok = vim.wait(5000, fn, 50)
	check(name, ok, "timed out")
	return ok
end

local function float_lines()
	return vim.api.nvim_buf_get_lines(threads._state.buf, 0, -1, false)
end

-- 1. multi-line comment THROUGH THE KEYMAP: a visual mapping runs with the
-- selection still active, and reading '< / '> there would comment the
-- previous selection instead — the exact bug this step pins.
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.api.nvim_feedkeys("Vjmc", "mx", false)
wait_for("compose opens", function()
	return vim.bo[vim.api.nvim_get_current_buf()].buftype == "acwrite"
end)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "smoke: both lines are one comment" })
vim.cmd("w")
wait_for("comment filed", function() return #sync_list() == 1 end)

-- 2. thread float: the fragment is marked on BOTH lines, highlighted too
threads.open(docbuf)
wait_for("float opens", function() return vim.api.nvim_win_is_valid(threads._state.win) end)
if vim.api.nvim_win_is_valid(threads._state.win) then
	local lines = float_lines()
	local marked = vim.tbl_filter(function(l) return l:sub(1, 2) == "> " end, lines)
	check("fragment marked on both lines", #marked == 2,
		("%d marked: %s"):format(#marked, table.concat(marked, " | ")))
	local marks = vim.api.nvim_buf_get_extmarks(threads._state.buf,
		vim.api.nvim_create_namespace("mdrev-threads"), 0, -1, {})
	check("fragment highlighted on both lines", #marks >= 2, ("%d extmarks"):format(#marks))

	-- 3. reply through the float's compose
	threads._reply()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "smoke: replied" })
	vim.cmd("w")
	wait_for("reply lands", function() return #(sync_list()[1].replies or {}) == 1 end)
wait_for("reply shown in float", function()
	return #vim.tbl_filter(function(l)
		return l:find("smoke: replied", 1, true)
	end, float_lines()) == 1
end)

	-- 4. resolve: float closes, review clean
	threads._resolve()
	wait_for("review clean", function() return #sync_list() == 0 end)
	wait_for("float closed", function() return not vim.api.nvim_win_is_valid(threads._state.win) end)
end

-- 5. `mc` with no selection comments the line under the cursor: mdrev
-- quotes the line's first words itself.
vim.api.nvim_win_set_cursor(0, { 6, 0 })
vim.api.nvim_feedkeys("mc", "mx", false)
wait_for("line compose opens", function()
	return vim.bo[vim.api.nvim_get_current_buf()].buftype == "acwrite"
end)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "smoke: line comment" })
vim.cmd("w")
wait_for("line comment filed", function() return #sync_list() == 1 end)
check("line comment anchors on the line's words",
	sync_list()[1].selected_text == "Beta paragraph after a blank.")

-- 5. the language server config is loadable from the runtimepath
local cfg = vim.lsp.config["mdrev"]
check("lsp config on runtimepath", cfg ~= nil and cfg.filetypes ~= nil)

if #failed > 0 then
	vim.cmd("cq 1")
else
	vim.cmd("qa!")
end
