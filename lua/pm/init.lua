local M = {}

local cfg = {
	spec_map = {},
	ensured = false,
}

local function log(msg)
	vim.notify("[pm] " .. msg, vim.log.levels.INFO)
end

local function expand_short_url(url)
	if url:match("^[%w%-_]+/[%w%-_]+$") then
		return "https://github.com/" .. url
	end
	return url
end

local function name_from_url(url)
	return (url:match("([^/]+)%.git$") or url:match("([^/]+)$"))
end

function M.setup(plugins)
	if cfg.ensured then
		return
	end -- idempotent
	cfg.ensured = true

	local to_add = {}
	for _, spec in ipairs(plugins) do
		local t = type(spec) == "string" and { src = spec } or spec
		t.src = expand_short_url(t.src)
		t.name = t.name or name_from_url(t.src)

		cfg.spec_map[t.name] = t

		if t.lazy or t.ft or t.cmd then
			t.load = false
			t.data = t.data or {}
			t.data.lazy_ft = t.ft
			t.data.lazy_cmd = t.cmd
		end

		table.insert(to_add, t)
	end

	vim.pack.add(to_add, { confirm = false })

	for _, info in ipairs(vim.pack.get()) do
		local spec = info.spec
		local lazy = spec.data or {}

		if lazy.lazy_ft then
			local pattern = type(lazy.lazy_ft) == "table" and lazy.lazy_ft or { lazy.lazy_ft }
			vim.api.nvim_create_autocmd("FileType", {
				pattern = pattern,
				once = true,
				callback = function()
					vim.cmd.packadd(spec.name)
					if spec.config then
						spec.config()
					end
				end,
			})
		end

		if lazy.lazy_cmd then
			local cmds = type(lazy.lazy_cmd) == "table" and lazy.lazy_cmd or { lazy.lazy_cmd }
			for _, c in ipairs(cmds) do
				vim.api.nvim_create_user_command(c, function(opts)
					vim.cmd.packadd(spec.name)
					if spec.config then
						spec.config()
					end

					vim.cmd(c .. " " .. opts.args)
				end, { nargs = "*", force = true })
			end
		end

		if spec.load ~= false and spec.config then
			spec.config()
		end
	end
end

function M.update(names, opts)
	names = names or vim.tbl_keys(cfg.spec_map)
	vim.pack.update(names, opts or {})
end

function M.sync(opts)
	opts = opts or {}
	local wanted = vim.tbl_keys(cfg.spec_map)
	local existing = vim.tbl_map(function(i)
		return i.spec.name
	end, vim.pack.get())
	local missing = vim.tbl_filter(function(n)
		return not vim.tbl_contains(existing, n)
	end, wanted)
	local extra = vim.tbl_filter(function(n)
		return not vim.tbl_contains(wanted, n)
	end, existing)

	if #missing > 0 then
		log("Installing missing: " .. table.concat(missing, ", "))
		vim.pack.add(
			vim.tbl_map(function(n)
				return cfg.spec_map[n]
			end, missing),
			{ confirm = false }
		)
	end

	if not opts.keep_unused and #extra > 0 then
		log("Removing extra: " .. table.concat(extra, ", "))
		vim.pack.del(extra)
	end
end

function M.clean(opts)
	opts = opts or {}
	M.sync(vim.tbl_extend("force", opts, { keep_unused = false }))
end

function M.pin(name, ref)
	local spec = cfg.spec_map[name]
	if not spec then
		vim.notify("[pm] unknown plugin " .. name, vim.log.levels.ERROR)
		return
	end
	spec.version = ref or vim.pack.get({ name })[1].rev
	log(string.format("%s pinned to %s", name, spec.version))
end

function M.unpin(name)
	local spec = cfg.spec_map[name]
	if spec then
		spec.version = nil
	end
	log(name .. " unpinned")
end

function M.get(name)
	local info = vim.pack.get({ name })[1]
	return info and info.spec
end

return M
