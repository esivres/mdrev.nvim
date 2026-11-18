-- Browser preview: `mdrev preview` serves the file from disk; one process
-- per file, as many files as the reviewer opens. Lives as long as this
-- Neovim does. Attached vim.system children are promised that death, but
-- only an explicit kill makes it certain on every exit path (LazyVim can
-- cut the VimLeavePre chain short), so both events carry it.
local cli = require("mdrev.cli")

local M = { procs = {} }

local function leave_kill()
	for file, entry in pairs(M.procs) do
		pcall(function()
			entry.proc:kill()
		end)
		M.procs[file] = nil
	end
end

local function guard(buf)
	local file = vim.api.nvim_buf_get_name(buf)
	if file == "" then
		vim.notify("mdrev: the buffer has no file", vim.log.levels.WARN)
		return nil
	end
	-- The server reads the document from disk: a dirty buffer would preview
	-- stale text and anchor new comments against it.
	if vim.bo[buf].modified then
		vim.notify("mdrev: save the buffer first — preview serves the file from disk",
			vim.log.levels.WARN)
		return nil
	end
	return file
end

function M.open(buf)
	local file = guard(buf)
	if not file then
		return
	end
	-- Same file again: the watcher already keeps the page current, so just
	-- remind the reviewer where it lives.
	local running = M.procs[file]
	if running and running.proc then
		vim.notify("mdrev: preview already at " .. (running.url or "its port"), vim.log.levels.INFO)
		return
	end
	local group = vim.api.nvim_create_augroup("mdrev-preview", { clear = true })
	for _, event in ipairs({ "VimLeavePre", "VimLeave" }) do
		vim.api.nvim_create_autocmd(event, {
			group = group,
			callback = leave_kill,
		})
	end
	local launched, proc = pcall(vim.system, { cli.bin(), "preview", file }, {
		text = true,
		stdout = function(err, data)
			-- The server prints its URL as the first (only) stdout line.
			if not err and data and data:match("^http") then
				local url = data:gsub("%s+", "")
				local entry = M.procs[file]
				if entry then
					entry.url = url
				end
				vim.schedule(function()
					vim.notify("mdrev: preview at " .. url)
				end)
			end
		end,
	}, function(out)
		M.procs[file] = nil
		if out.code ~= 0 then
			vim.schedule(function()
				vim.notify("mdrev: preview stopped: " .. (out.stderr or ("exit " .. out.code)),
					vim.log.levels.WARN)
			end)
		end
	end)
	if not launched then
		vim.notify("mdrev: " .. proc, vim.log.levels.ERROR)
		return
	end
	M.procs[file] = { proc = proc }
end

return M
