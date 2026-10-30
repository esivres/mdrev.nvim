-- Commenting: on a visual selection the quote is the selected lines; with
-- nothing selected mdrev anchors on the start of the line itself (no
-- --quote). The disambiguating line is a pass-through: cursor rows and MRSF
-- `--line` are both 1-based.
local cli = require("mdrev.cli")
local compose = require("mdrev.compose")

local M = {}

local function file_of(buf)
	local file = vim.api.nvim_buf_get_name(buf)
	if file == "" then
		vim.notify("mdrev: the buffer has no file", vim.log.levels.WARN)
		return nil
	end
	-- mdrev anchors against the file on disk; a dirty buffer would anchor
	-- the comment against text that is not there yet.
	if vim.bo[buf].modified then
		vim.notify("mdrev: save the buffer first — comments anchor against the file",
			vim.log.levels.WARN)
		return nil
	end
	return file
end

local function compose_comment(title, file, anchor, row)
	compose.open(title, function(text, done)
		local args = { cli.bin(), "comment", "--file", file }
		vim.list_extend(args, anchor)
		vim.list_extend(args, { "--line", tostring(row + 1), "--text", text })
		cli.run(args, function(ok, _, err)
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

-- On a selection: the quote is the selected lines.
function M.comment(buf, srow, erow)
	local file = file_of(buf)
	if not file then
		return
	end
	local quote = table.concat(vim.api.nvim_buf_get_lines(buf, srow, erow + 1, false), "\n")
	compose_comment("comment", file, { "--quote", quote }, srow)
end

-- On a line, no selection: mdrev quotes the line's first words itself.
function M.line(buf, row)
	local file = file_of(buf)
	if not file then
		return
	end
	compose_comment("comment on line " .. (row + 1), file, {}, row)
end

return M
