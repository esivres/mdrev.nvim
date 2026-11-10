-- The compose float, after review.nvim: a type selector row above a
-- markdown input, centered on the screen. Tab cycles the type (in insert
-- mode too), C-s or :w files the comment, Esc/q discards. The saver decides
-- when the float may close, so a failed write keeps the text on screen.
local M = {}

local ns = vim.api.nvim_create_namespace("mdrev-compose")
-- Smoke-test hook; not part of the user surface.
local state = { types = nil, type_idx = 1, sel_win = -1, sel_buf = -1, win = -1, buf = -1, close = nil }
M._state = state

local function label(t)
	return t == "" and "comment" or t
end

local function render_types()
	local sep = "  "
	local line, at = {}, {}
	local col = 0
	for i, t in ipairs(state.types) do
		at[i] = col
		local part = i == state.type_idx and ("[ " .. label(t) .. " ]") or ("  " .. label(t) .. "  ")
		line[#line + 1] = part
		col = col + #part + #sep
	end
	local sel = state.type_idx
	vim.api.nvim_buf_set_lines(state.sel_buf, 0, -1, false, { table.concat(line, sep) })
	vim.api.nvim_buf_clear_namespace(state.sel_buf, ns, 0, -1)
	vim.api.nvim_buf_add_highlight(state.sel_buf, ns, "Special", 0, at[sel], at[sel] + #("[ " .. label(state.types[sel]) .. " ]"))
end

-- opts: title (float title), types (list; nil hides the selector, first
-- entry is the default), on_save(type, text, done(failed)).
function M.open(opts)
	-- A repeat open must replace the previous float, or its windows stay
	-- with dead mappings forever.
	if state.close then
		state.close()
	end
	local types = opts.types
	state.types = types
	state.type_idx = 1

	local width = math.min(60, vim.o.columns - 4)
	local input_h = 6
	local total = input_h + 2 + (types and 3 or 0) -- +2: the input border
	local row = math.floor((vim.o.lines - total) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	if types then
		state.sel_buf = vim.api.nvim_create_buf(false, true)
		state.sel_win = vim.api.nvim_open_win(state.sel_buf, false, {
			relative = "editor",
			row = row,
			col = col,
			width = width,
			height = 1,
			border = "rounded",
			title = { { " type (Tab) ", "Title" } },
			title_pos = "center",
			style = "minimal",
			focusable = false,
		})
		render_types()
	end

	local buf = vim.api.nvim_create_buf(false, true)
	-- A name is required for `:w` to reach BufWriteCmd on an acwrite buffer;
	-- the handler intercepts the write, so the temp path never touches disk.
	vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".md")
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].filetype = "markdown"
	state.buf = buf
	state.win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = row + (types and 3 or 0),
		col = col,
		width = width,
		height = input_h,
		border = "rounded",
		title = { { " " .. opts.title .. " · C-s save · q discard ", "Title" } },
		title_pos = "center",
		style = "minimal",
	})

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if vim.api.nvim_win_is_valid(state.sel_win) then
			vim.api.nvim_win_close(state.sel_win, false)
		end
		if vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_win_close(state.win, false)
		end
	end
	state.close = close

	local busy = false
	local function submit()
		-- A second save while the first is still in flight (the lock retry
		-- alone takes 150 ms) would file the comment twice.
		if closed or busy then
			return
		end
		local text = (table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):gsub("%s+$", ""))
		if text == "" then
			close() -- nothing typed: same as discard
			return
		end
		busy = true
		opts.on_save(types and types[state.type_idx] or nil, text, function(failed)
			if failed then
				busy = false -- the text stays on screen, re-saveable
			else
				close()
			end
		end)
	end

	if types then
		vim.keymap.set({ "i", "n" }, "<Tab>", function()
			state.type_idx = state.type_idx % #types + 1
			render_types()
		end, { buffer = buf })
	end
	vim.keymap.set({ "i", "n" }, "<C-s>", submit, { buffer = buf })
	vim.keymap.set("n", "<CR>", submit, { buffer = buf })
	vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })
	-- `:w` keeps working through the acwrite contract.
	vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = buf, callback = submit })
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(state.win),
		once = true,
		callback = function()
			closed = true
			-- Closing the windows must not leak their scratch buffers.
			for _, b in ipairs({ state.sel_buf, buf }) do
				if vim.api.nvim_buf_is_valid(b) then
					vim.api.nvim_buf_delete(b, { force = true })
				end
			end
		end,
	})

	vim.cmd("startinsert")
	return state.win
end

return M
