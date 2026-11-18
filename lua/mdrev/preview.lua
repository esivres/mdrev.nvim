-- Browser preview: `mdrev preview` serves the file from disk and lives as
-- long as this Neovim does. Attached vim.system children are promised that
-- death, but only an explicit VimLeavePre kill makes it certain on every
-- exit path, so both are used.
local cli = require("mdrev.cli")

local M = { proc = nil }

local function leave_kill()
	if M.proc then
		M.proc:kill()
		M.proc = nil
	end
end

function M.open(buf)
	local file = vim.api.nvim_buf_get_name(buf)
	if file == "" then
		vim.notify("mdrev: the buffer has no file", vim.log.levels.WARN)
		return
	end
	-- The server reads the document from disk: a dirty buffer would preview
	-- stale text and anchor new comments against it.
	if vim.bo[buf].modified then
		vim.notify("mdrev: save the buffer first — preview serves the file from disk",
			vim.log.levels.WARN)
		return
	end
	if M.proc then
		vim.notify("mdrev: preview already running for this editor", vim.log.levels.INFO)
		return
	end
	local group = vim.api.nvim_create_augroup("mdrev-preview", { clear = true })
	-- VimLeavePre chains can be cut short by an earlier handler's error (seen
	-- under LazyVim), so the later event carries the same kill as a backup.
	for _, event in ipairs({ "VimLeavePre", "VimLeave" }) do
		vim.api.nvim_create_autocmd(event, {
			group = group,
			callback = function()
				pcall(leave_kill)
			end,
		})
	end
	local launched, proc = pcall(vim.system, { cli.bin(), "preview", file }, {
		text = true,
		stdout = function(err, data)
			-- The server prints its URL as the first (only) stdout line.
			if not err and data and data:match("^http") then
				vim.schedule(function()
					vim.notify("mdrev: preview at " .. data:gsub("%s+", ""))
				end)
			end
		end,
	}, function(out)
		M.proc = nil
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
	M.proc = proc
end

return M
