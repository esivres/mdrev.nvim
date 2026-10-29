-- Async wrapper around the mdrev CLI: every action the language server
-- cannot do (typed comments, replies, resolve, listing) goes through here.
local M = { _bin = "mdrev" }

function M.setup(opts)
	M._bin = (opts and opts.cmd) or M._bin
end

function M.bin()
	return M._bin
end

local LOCKED = "another mdrev is writing"

-- run(args, cb(ok, stdout, stderr)) retries once on lock contention: the
-- editor's own language server may be mid-write into the same sidecar.
function M.run(args, cb)
	local function attempt(n)
		local launched, proc = pcall(vim.system, args, { text = true }, function(out)
			vim.schedule(function()
				if out.code ~= 0 and n == 1 and (out.stderr or ""):find(LOCKED, 1, true) then
					vim.defer_fn(function()
						attempt(2)
					end, 150)
					return
				end
				cb(out.code == 0, out.stdout or "", out.stderr or "")
			end)
		end)
		if not launched then
			-- vim.system raises synchronously when the binary is missing.
			cb(false, "", proc)
		end
	end
	attempt(1)
end

-- list(file, cb(ok, threads, err)) — open threads only, in `list --json` shape.
function M.list(file, cb)
	M.run({ M._bin, "list", file, "--json" }, function(ok, out, err)
		local threads = {}
		if ok and out ~= "" then
			local decoded, parsed = pcall(vim.json.decode, out)
			ok, threads = ok and decoded, decoded and parsed or {}
		end
		cb(ok, threads, err)
	end)
end

return M
