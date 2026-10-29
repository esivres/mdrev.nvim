-- The thread float: the paragraph a comment is about, the comment with its
-- replies, and one-key actions. Display only — all state lives in the
-- sidecar, reached through the CLI, so the language server, the terminal UI
-- and this float never disagree for long.
local cli = require("mdrev.cli")
local compose = require("mdrev.compose")

local M = {}
local ns = vim.api.nvim_create_namespace("mdrev-threads")
local state = { threads = {}, idx = 1, win = -1, buf = -1, doc = "" }

-- The paragraph around a line, blank-line bounded, as the terminal UI shows it.
local function paragraph(buf, line)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	line = math.max(1, math.min(line, #lines))
	local top, bot = line, line
	while top > 1 and lines[top - 1] ~= "" do
		top = top - 1
	end
	while bot < #lines and lines[bot + 1] ~= "" do
		bot = bot + 1
	end
	return vim.list_slice(lines, top, bot), top
end

-- First and last document line of the anchored fragment: a multi-line quote
-- must read as one marked fragment, not as a marked line plus loose text.
local function fragment_span(t)
	local n = #vim.split(t.selected_text or "", "\n", { plain = true })
	local first = t.line or 1
	return first, first + math.max(n - 1, 0)
end

local function render()
	local t = state.threads[state.idx]
	if not t or not vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local docbuf = vim.fn.bufnr(state.doc)
	if docbuf <= 0 then
		return
	end

	local first, last = fragment_span(t)
	local para, top = paragraph(docbuf, first)
	local content = {}
	for i, l in ipairs(para) do
		local docline = top + i - 1
		table.insert(content, (docline >= first and docline <= last) and ("> " .. l) or ("  " .. l))
	end

	table.insert(content, "")
	local function push(prefix, s)
		for _, l in ipairs(vim.split(s or "", "\n", { plain = true })) do
			table.insert(content, prefix .. l)
		end
	end
	local kind = (t.type and t.type ~= "") and (" · " .. t.type) or ""
	local head = t.author .. kind .. ": "
	if t.orphaned then
		head = "[anchor lost] " .. head
	end
	push(head, t.text)
	for _, r in ipairs(t.replies or {}) do
		push("    " .. (r.author or "?") .. ": ", r.text)
	end
	if t.x_suggested_text and t.x_suggested_text ~= "" then
		push("    suggestion: ", t.x_suggested_text)
	end
	table.insert(content, "")
	table.insert(content, ("%d/%d  [r] reply  [x] resolve  [j]/[k] thread  [q] close")
		:format(state.idx, #state.threads))

	local buf, win = state.buf, state.win
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	vim.api.nvim_win_set_config(win, { height = math.min(#content, vim.o.lines - 4) })

	-- Highlight the fragment inside the paragraph, line by line.
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local frag = vim.split(t.selected_text or "", "\n", { plain = true })
	for i, l in ipairs(content) do
		local docline = top + i - 1
		if docline >= first and docline <= last and l:sub(1, 1) == ">" then
			local seg = frag[docline - first + 1] or ""
			local s = seg ~= "" and l:find(seg, 3, true)
			if s then
				vim.highlight.range(buf, ns, "Search", { i - 1, s - 1 }, { i - 1, s - 1 + #seg })
			end
		end
	end
	vim.api.nvim_win_set_cursor(win, { 1, 0 })
end

local function cycle(d)
	if #state.threads == 0 then
		return
	end
	state.idx = ((state.idx - 1 + d + #state.threads) % #state.threads) + 1
	render()
end

local function refresh(cb)
	cli.list(state.doc, function(ok, threads, err)
		if not ok then
			vim.notify("mdrev: " .. err, vim.log.levels.ERROR)
			return
		end
		for _, t in ipairs(threads) do
			t._doc = state.doc
		end
		state.threads = threads
		if state.idx > #threads then
			state.idx = math.max(1, #threads)
		end
		if cb then
			cb(#threads)
		end
	end)
end

local function reply()
	local t = state.threads[state.idx]
	if not t then
		return
	end
	local file = t._doc
	compose.open("reply to " .. t.id:sub(1, 8), function(text, done)
		cli.run({ cli.bin(), "reply", "--file", file, "--id", t.id, "--text", text },
			function(ok, _, err)
				if not ok then
					vim.notify("mdrev: " .. err, vim.log.levels.ERROR)
					done(true) -- keep the float armed for a retry
					return
				end
				done()
				refresh(function() render() end)
			end)
	end)
end

local function resolve()
	local t = state.threads[state.idx]
	if not t then
		return
	end
	cli.run({ cli.bin(), "resolve", "--file", t._doc, "--id", t.id }, function(ok, _, err)
		if not ok then
			vim.notify("mdrev: " .. err, vim.log.levels.ERROR)
			return
		end
		refresh(function(n)
			if n == 0 then
				if vim.api.nvim_win_is_valid(state.win) then
					vim.api.nvim_win_close(state.win, false)
				end
				vim.notify("mdrev: review clean")
			else
				render()
			end
		end)
	end)
end

-- The float with the thread nearest the cursor row. Takes the document
-- buffer explicitly: the current buffer may be a compose float.
function M.open(buf)
	-- A second open (the command is repeatable) must replace the previous
	-- float, or its window stays with dead mappings forever.
	if vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, false)
	end
	state.doc = vim.api.nvim_buf_get_name(buf or 0)
	local row = vim.fn.line(".")
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
		state.win = vim.api.nvim_open_win(state.buf, true, {
			relative = "editor",
			anchor = "NE",
			col = vim.o.columns - 2,
			row = 1,
		width = math.min(76, vim.o.columns - 4),
		height = 5,
		-- A title shows only with a border.
		border = "rounded",
		title = { { " mdrev threads ", "Title" } },
		title_pos = "center",
		style = "minimal",
	})
		vim.keymap.set("n", "q", function()
			if vim.api.nvim_win_is_valid(state.win) then
				vim.api.nvim_win_close(state.win, false)
			end
		end, { buffer = state.buf, silent = true })
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
	end)
end

-- Smoke-test hooks; not part of the user surface.
M._state, M._reply, M._resolve, M._render = state, reply, resolve, render

return M
