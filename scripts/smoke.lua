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

local function panel_lines()
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
local compose_state = require("mdrev.compose")._state
local function sel_line()
	return vim.api.nvim_buf_get_lines(compose_state.sel_buf, 0, -1, false)[1] or ""
end
check("selector shows the default type", sel_line():find("%[ comment %]", 1, false) ~= nil, sel_line())
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "smoke: both lines are one comment" })
vim.cmd("w")
wait_for("comment filed", function() return #sync_list() == 1 end)

-- 2. threads panel: a real split (not a float), quote and discussion of
-- every thread in it, selection highlighted, document cursor following.
threads.open(docbuf)
wait_for("panel opens", function() return vim.api.nvim_win_is_valid(threads._state.win) end)
if vim.api.nvim_win_is_valid(threads._state.win) then
	check("panel is a split, not a float",
		vim.api.nvim_win_get_config(threads._state.win).relative == "")
	check("panel shows the quoted fragment",
		#vim.tbl_filter(function(l) return l:find("› Alpha paragraph", 1, true) end,
			panel_lines()) == 1)
	local marks = vim.api.nvim_buf_get_extmarks(threads._state.buf,
		vim.api.nvim_create_namespace("mdrev-threads"), 0, -1, {})
	check("selection highlighted", #marks == 1, ("%d extmarks"):format(#marks))
	check("document cursor follows the anchor",
		vim.fn.line(".", threads._state.docwin) == sync_list()[1].line,
		("curline=%s want=%s"):format(vim.fn.line(".", threads._state.docwin),
			tostring(sync_list()[1] and sync_list()[1].line)))

	-- 3. reply through the panel's compose
	threads._reply()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "smoke: replied" })
	vim.cmd("w")
	wait_for("reply lands", function() return #(sync_list()[1].replies or {}) == 1 end)
	wait_for("reply shown in panel", function()
		return #vim.tbl_filter(function(l)
			return l:find("smoke: replied", 1, true)
		end, panel_lines()) == 1
	end)

	-- 4. resolve: panel closes, review clean
	threads._resolve()
	wait_for("review clean", function() return #sync_list() == 0 end)
	wait_for("panel closed", function() return not vim.api.nvim_win_is_valid(threads._state.win) end)
end

-- 5. `mc` with no selection comments the line under the cursor, through
-- the new keys: Tab picks the type, C-s files the comment.
vim.api.nvim_win_set_cursor(0, { 6, 0 })
vim.api.nvim_feedkeys("mc", "mx", false)
wait_for("line compose opens", function()
	return vim.bo[vim.api.nvim_get_current_buf()].buftype == "acwrite"
end)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "smoke: line comment" })
vim.api.nvim_feedkeys("\t", "mx", false)
wait_for("Tab cycles the type", function()
	return sel_line():find("%[ issue %]", 1, false) ~= nil
end)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-s>", true, false, true), "mx", false)
wait_for("line comment filed", function() return #sync_list() == 1 end)
check("comment carries the picked type", sync_list()[1].type == "issue",
	vim.inspect(sync_list()[1].type))
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
