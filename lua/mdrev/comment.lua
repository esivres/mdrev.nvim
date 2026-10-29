-- Commenting a visual selection: the quote is the selected lines, the
-- disambiguating line is the first selected row (cursor rows and MRSF
-- `--line` are both 1-based, so this is a pass-through).
local cli = require("mdrev.cli")
local compose = require("mdrev.compose")

local M = {}

function M.comment(buf, srow, erow)
	local file = vim.api.nvim_buf_get_name(buf)
	if file == "" then
		vim.notify("mdrev: the buffer has no file", vim.log.levels.WARN)
		return
	end
	-- mdrev anchors against the file on disk; a dirty buffer would anchor
	-- the comment against text that is not there yet.
	if vim.bo[buf].modified then
		vim.notify("mdrev: save the buffer first — comments anchor against the file",
			vim.log.levels.WARN)
		return
	end

	local quote = table.concat(vim.api.nvim_buf_get_lines(buf, srow, erow + 1, false), "\n")
	compose.open("comment", function(text, done)
		cli.run({
			cli.bin(), "comment", "--file", file, "--quote", quote,
			"--line", tostring(srow + 1), "--text", text,
		}, function(ok, _, err)
			if not ok then
				vim.notify("mdrev: " .. err, vim.log.levels.ERROR)
				done(true) -- keep the float armed for a retry
				return
			end
			vim.notify("mdrev: comment filed")
			done()
		end)
	end)
end

return M
