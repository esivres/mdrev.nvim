if vim.g.loaded_mdrev then
	return
end
vim.g.loaded_mdrev = true

vim.api.nvim_create_user_command("MdrevComment", function(ctx)
	require("mdrev.comment").comment(0, ctx.line1 - 1, ctx.line2 - 1)
end, { range = true, desc = "mdrev: comment the selected lines" })

vim.api.nvim_create_user_command("MdrevThreads", function()
	require("mdrev.threads").open()
end, { desc = "mdrev: thread nearest the cursor" })
