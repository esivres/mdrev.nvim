-- The compose float: a markdown scratch buffer; `:w` saves through a
-- BufWriteCmd handler, `:q` (or `q`) discards. The saver decides when the
-- float may close, so a failed write keeps the text on screen.
local M = {}

function M.open(title, on_save)
	local buf = vim.api.nvim_create_buf(false, true)
	-- A name is required for `:w` to reach BufWriteCmd on an acwrite buffer;
	-- the handler intercepts the write, so the temp path never touches disk.
	vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".md")
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].filetype = "markdown"

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = math.min(72, vim.o.columns - 4),
		height = math.min(10, vim.o.lines - 4),
		border = "rounded",
		title = { { " mdrev: " .. title .. " (:w saves, :q discards) ", "Title" } },
		title_pos = "center",
		style = "minimal",
	})

	local closed = false
	local function close()
		if not closed and vim.api.nvim_win_is_valid(win) then
			closed = true
			vim.api.nvim_win_close(win, false)
		end
	end

	vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
	local busy = false
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			-- A second :w while the first save is still in flight (the lock
			-- retry alone takes 150 ms) would file the comment twice.
			if busy then
				return
			end
			local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
			if text ~= "" then
				busy = true
				on_save(text, function(failed)
					if failed then
						busy = false -- the text stays on screen, re-saveable
					else
						close()
					end
				end)
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			vim.api.nvim_buf_delete(buf, { force = true })
		end,
	})
	return win
end

return M
