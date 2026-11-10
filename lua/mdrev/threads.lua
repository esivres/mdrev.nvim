-- The threads panel: a right-hand split with every open thread — quote,
-- discussion, replies — instead of a float. j/k walk the threads and move
-- the document cursor to the anchor, so the context is the document itself.
-- Display only — all state lives in the sidecar, reached through the CLI,
-- so the language server, the terminal UI and this panel never disagree
-- for long.
local cli = require("mdrev.cli")
local compose = require("mdrev.compose")

local M = {}
local ns = vim.api.nvim_create_namespace("mdrev-threads")
local state = { threads = {}, idx = 1, win = -1, buf = -1, doc = "", docwin = -1 }

-- The first document line of the anchored fragment; the panel jumps there.
local function anchor_line(t)
	return t.line or 1
end

local function close()
	if vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, false)
	end
end

-- Each thread becomes a block; the selected one is highlighted whole.
local function blocks()
	local out, span = {}, {}
	for i, t in ipairs(state.threads) do
		local first = #out + 1
		local kind = (t.type and t.type ~= "") and t.type or "comment"
		local head = ("%d · line %d · %s · %s"):format(i, t.line or 1, kind, t.author or "?")
		if t.orphaned then
			head = "[anchor lost] " .. head
		end
		table.insert(out, head)
		local function push(prefix, s)
			for _, l in ipairs(vim.split(s or "", "\n", { plain = true })) do
				table.insert(out, prefix .. l)
			end
		end
		push("  › ", t.selected_text)
		push("  ", t.text)
		for _, r in ipairs(t.replies or {}) do
			push("      " .. (r.author or "?") .. ": ", r.text)
		end
		if t.x_suggested_text and t.x_suggested_text ~= "" then
			push("      suggestion: ", t.x_suggested_text)
		end
		span[i] = { first, #out }
		table.insert(out, "")
	end
	return out, span
end

local function render()
	local t = state.threads[state.idx]
	if not t or not vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local content, span = blocks()
	table.insert(content, ("%d/%d  [j]/[k] thread  [r] reply  [x] resolve  [q] close")
		:format(state.idx, #state.threads))

	local buf, win = state.buf, state.win
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local sel = span[state.idx]
	if sel then
		vim.api.nvim_buf_set_extmark(buf, ns, sel[1] - 1, 0, {
			end_line = sel[2],
			line_hl_group = "Visual",
		})
		vim.api.nvim_win_set_cursor(win, { sel[1], 0 })
	end
end

-- Selection moves the document cursor with it: the panel entry and the
-- paragraph it talks about stay in view together.
local function follow()
	local t = state.threads[state.idx]
	if t and vim.api.nvim_win_is_valid(state.docwin) then
		vim.api.nvim_win_set_cursor(state.docwin, { anchor_line(t), 0 })
	end
end

local function cycle(d)
	if #state.threads == 0 then
		return
	end
	state.idx = ((state.idx - 1 + d + #state.threads) % #state.threads) + 1
	render()
	follow()
end

local function refresh(cb)
	cli.list(state.doc, function(ok, threads, err)
		if not ok then
			vim.notify("mdrev: " .. err, vim.log.levels.ERROR)
			return
		end
		state.threads = threads
		if state.idx > #threads then
			state.idx = math.max(1, #threads)
		end
		cb(#threads)
	end)
end

local function after_action()
	refresh(function(n)
		if n == 0 then
			close()
			vim.notify("mdrev: review clean")
		else
			render()
		end
	end)
end

local function reply()
	local t = state.threads[state.idx]
	if not t then
		return
	end
	local file = state.doc
	compose.open({ title = "reply to " .. t.id:sub(1, 8), on_save = function(_, text, done)
		cli.run({ cli.bin(), "reply", "--file", file, "--id", t.id, "--text", text },
			function(ok, _, err)
				if not ok then
					vim.notify("mdrev: " .. err, vim.log.levels.ERROR)
					done(true) -- keep the float armed for a retry
					return
				end
				done()
				after_action()
			end)
	end })
end

local function resolve()
	local t = state.threads[state.idx]
	if not t then
		return
	end
	cli.run({ cli.bin(), "resolve", "--file", state.doc, "--id", t.id }, function(ok, _, err)
		if not ok then
			vim.notify("mdrev: " .. err, vim.log.levels.ERROR)
			return
		end
		after_action()
	end)
end

-- The panel with every thread of the document, `mt` toggles it. Takes the
-- document buffer explicitly: the current buffer may be a compose float.
function M.open(buf)
	-- A second open closes the panel; a stale window from a closed document
	-- must not keep dead mappings alive either.
	if vim.api.nvim_win_is_valid(state.win) then
		close()
		return
	end
	state.doc = vim.api.nvim_buf_get_name(buf or 0)
	-- The document's window, not the current one: mt may fire while a
	-- compose float is still closing and the current window is that float.
	state.docwin = vim.fn.bufwinid(buf or 0)
	if state.docwin == -1 then
		state.docwin = vim.api.nvim_get_current_win()
	end
	local row = vim.fn.line(".", state.docwin)
	refresh(function(n)
		if n == 0 then
			vim.notify("mdrev: review clean")
			return
		end
		local nearest, best = 1, math.huge
		for i, t in ipairs(state.threads) do
			local d = math.abs((t.line or 1) - row)
			if d < best then
				best, nearest = d, i
			end
		end
		state.idx = nearest

		state.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[state.buf].buftype = "nofile"
		state.win = vim.api.nvim_open_win(state.buf, true, { split = "right", win = state.docwin })
		vim.api.nvim_win_set_width(state.win, 46)
		vim.wo[state.win].wrap = false
		vim.keymap.set("n", "q", close, { buffer = state.buf, silent = true })
		vim.keymap.set("n", "<Esc>", close, { buffer = state.buf, silent = true })
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(state.win),
			once = true,
			callback = function()
				-- Closing the window must not leak its scratch buffer.
				if vim.api.nvim_buf_is_valid(state.buf) then
					vim.api.nvim_buf_delete(state.buf, { force = true })
				end
			end,
		})
		vim.keymap.set("n", "j", function() cycle(1) end, { buffer = state.buf })
		vim.keymap.set("n", "k", function() cycle(-1) end, { buffer = state.buf })
		vim.keymap.set("n", "r", reply, { buffer = state.buf })
		vim.keymap.set("n", "x", resolve, { buffer = state.buf })
		render()
		follow()
	end)
end

-- Smoke-test hooks; not part of the user surface.
M._state, M._reply, M._resolve, M._render = state, reply, resolve, render

return M
