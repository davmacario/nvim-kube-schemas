local attach = require("nvim-kube-schemas.attach")
local cache_mgmt = require("nvim-kube-schemas.cache-management")
local curl = require("nvim-kube-schemas.curl")

---@class NvimKubeSchemaConfig
---@field enabled boolean: set to false to disable plugin
---@field cache_root string: path where yaml schemas are cached (root)
---@field pattern string[]: list of patterns used to define autocmd. Should
---													match the file types where yamlls is used.
---@field augroup string|integer?: autocmd group that owns the autocmd. if nil,
---													will create one.
local DEFAULTS = {
	enabled = true,
	cache_root = vim.fs.joinpath(vim.fn.stdpath("data"), "yaml-schemas"),
	augroup = nil,
	pattern = { "*.yaml", "*.yml" },
}

local config = DEFAULTS

local M = {
	setup_called = false,
}

-- Entrypoint into the plugin.
-- Configures autocmd running plugin.init()
M.create_autocmd = function()
	local augroup = config.augroup
	if not augroup then
		augroup = vim.api.nvim_create_augroup("NvimKubeSchemas", { clear = true })
	elseif type(augroup) == "string" then
		augroup = vim.api.nvim_create_augroup(augroup, { clear = false })
	end

	vim.api.nvim_create_autocmd({ "LspAttach", "BufEnter" }, {
		group = augroup,
		pattern = config.pattern,
		callback = function(args)
			local bufnr = args.buf
			local clients = vim.lsp.get_clients({ bufnr = bufnr })
			for _, client in ipairs(clients) do
				if client.name == "yamlls" then
					attach.init(bufnr)
					return
				end
			end
		end,
	})
end

---Delete every cached schema, then reset the state that would otherwise keep
---serving it for the rest of the session.
---@param opts { force: boolean? }?: if `force` is true, force deletion
M.clear_cache = function(opts)
	opts = opts or {}

	local n_files = cache_mgmt.count_files()

	if not opts.force and n_files > 0 then
		local choice = vim.fn.confirm(
			("Delete %d file(s) from %s?"):format(n_files, cache_mgmt.cache_root),
			"&Yes\n&No",
			2 -- Default to "No": this is a recursive delete
		)
		if choice ~= 1 then
			return
		end
	end

	local ok, err = cache_mgmt.clear()
	if not ok then
		vim.notify("nvim-kube-schemas: " .. tostring(err), vim.log.levels.ERROR)
		-- The cache is still intact, so leave the buffers attached to it
		return
	end

	-- attach.init() early-returns while either flag is set, so without clearing
	-- them no open buffer would ever re-fetch its schema
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.b[bufnr].schema_attached = nil
			vim.b[bufnr].schema_pending = nil
			vim.b[bufnr].schema_checked = nil
		end
	end

	-- NOTE: entries in yamlls' `yaml.schemas` map are deliberately left in place.
	-- They get re-added on the next attach, and yamlls tolerates a schema path
	-- that does not resolve. Pruning them would mean tracking which keys we own.

	-- Otherwise an in-flight offline backoff would silently skip the re-fetch
	curl.offline_until = nil

	if n_files == 0 then
		vim.notify("nvim-kube-schemas: cache is already empty", vim.log.levels.INFO)
	else
		vim.notify(
			("nvim-kube-schemas: cleared %d cached file(s)"):format(n_files),
			vim.log.levels.INFO
		)
	end
end

M.create_user_commands = function()
	vim.api.nvim_create_user_command("NvimKubeSchemasClearCache", function(cmd_opts)
		M.clear_cache({ force = cmd_opts.bang })
	end, {
		bang = true,
		desc = "Delete all cached Kubernetes and CRD YAML schemas",
	})
end

---Configure nvim-kube-schemas plugin
---@param opts NvimKubeSchemaConfig?
M.setup = function(opts)
	if M.setup_called then
		return
	end

	if vim.fn.has("nvim-0.11") == 0 then
		vim.notify("This plugin requires Neovim >= 0.11", vim.log.levels.ERROR)
		return
	end

	---@type NvimKubeSchemaConfig
	config = vim.tbl_extend("force", config, opts or {})

	-- Check config
	if type(config.enabled) ~= "boolean" then
		vim.notify("nvim-kube-schemas: 'enabled' must be boolean", vim.log.levels.ERROR)
		return
	end
	if type(config.cache_root) ~= "string" then
		vim.notify("nvim-kube-schemas: 'cache_root' must be string", vim.log.levels.ERROR)
		return
	elseif vim.fn.mkdir(config.cache_root, "p") == 0 then
		vim.notify(
			"nvim-kube-schemas: unable to create 'cache_root' directory",
			vim.log.levels.ERROR
		)
		return
	end

	if
			config.augroup
			and type(config.augroup) ~= "string"
			and type(config.augroup) ~= "number"
	then
		vim.notify(
			"nvim-kube-schemas: 'augroup' must be string or integer",
			vim.log.levels.ERROR
		)
		return
	end
	-- TODO: check type of config.pattern

	M.setup_called = true

	cache_mgmt.cache_root = config.cache_root

	-- Registered even when disabled: reclaiming disk space is exactly what a user
	-- does after turning the plugin off
	M.create_user_commands()

	if not config.enabled then
		vim.notify("nvim-kube-schemas is disabled", vim.log.levels.INFO)
		return
	end

	M.create_autocmd()
end

M.get_config = function()
	return config
end

return M
