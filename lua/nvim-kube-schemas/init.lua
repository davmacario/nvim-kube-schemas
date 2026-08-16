local attach = require("nvim-kube-schemas.attach")
local cache_mgmt = require("nvim-kube-schemas.cache-management")

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

M.clear_cache = function()

end

M.create_user_commands = function()
	vim.api.nvim_create_user_command(
		"NvimKubeSchemasClearCache",
		function(opts)
			M.clear_cache()
		end,
		{desc = "Clean all cache directory"}
	)
end

---Configure nvim-kube-schemas plugin
---@param opts NvimKubeSchemaConfig?
M.setup = function(opts)
	if M.setup_called then
		return
	end
	M.setup_called = true

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

	if config.augroup and type(config.augroup) ~= "string" and type(config.augroup) ~= "number" then
		vim.notify(
			"nvim-kube-schemas: 'augroup' must be string or integer",
			vim.log.levels.ERROR
		)
		return
	end
	-- TODO: check type of config.pattern

	if not config.enabled then
		vim.notify("nvim-kube-schemas is disabled", vim.log.levels.INFO)
		return
	end

	cache_mgmt.cache_root = config.cache_root

	M.create_autocmd()
	-- create user commands
end

M.get_config = function()
	return config
end

return M
