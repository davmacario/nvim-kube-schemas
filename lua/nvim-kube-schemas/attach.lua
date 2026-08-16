local async = require("plenary.async")
local cache_mgmt = require("nvim-kube-schemas.cache-management")
local crds = require("nvim-kube-schemas.crds")
local k8s = require("nvim-kube-schemas.k8s-resources")

local M = {}

---Extract apiVersion and kind from YAML file content
---@param buffer_content string
---@return string?
---@return string?
M.extract_api_version_and_kind = function(buffer_content)
	-- FIXME: currently only matching 1st doc in multi-doc YAML (sep by ---)

	-- Remove the document separator (---) if present and add leading \n (helps with
	-- later)
	local content = "\n" .. buffer_content:gsub("^%-%-%-%s*\n", "")
	-- Scan the entire file for apiVersion and kind
	local api_version = content:match("\napiVersion:%s*([%w%.%/%-]+)")
	local kind = content:match("\nkind:%s*([%w%-]+)")
	return api_version, kind
end

---Attach a schema (from URL) to the buffer by updating yaml-language-server's
---configuration.
---NOTE: does not check for existence of `schema_src`
---@param bufnr integer: buffer to attach the schema to
---@param schema_src string: absolute path of the schema
---@param description string: description of the schema
M.attach_schema = function(bufnr, schema_src, description)
	local clients = vim.lsp.get_clients({ name = "yamlls", bufnr = bufnr })
	if #clients == 0 then
		vim.notify("yaml-language-server is not active.", vim.log.levels.WARN)
		return
	end
	-- Buffer file name
	local pattern = vim.api.nvim_buf_get_name(bufnr)

	local yaml_client = clients[1]

	-- Update the yaml.schemas setting for the current buffer
	yaml_client.config.settings = yaml_client.config.settings or {}
	yaml_client.config.settings.yaml = yaml_client.config.settings.yaml or {}
	yaml_client.config.settings.yaml.schemas = yaml_client.config.settings.yaml.schemas
		or {}

	-- yaml_client.config.settings.yaml.schemas maps a YAML schema URL to a
	-- list (or single string) of file patterns it should be attached to
	local existing = yaml_client.config.settings.yaml.schemas[schema_src]
	if type(existing) == "string" then
		existing = { existing }
	end
	existing = existing or {}
	if not vim.tbl_contains(existing, pattern) then
		table.insert(existing, pattern)
	end

	yaml_client.config.settings.yaml.schemas[schema_src] = existing

	-- Notify the server of the configuration change
	yaml_client:notify("workspace/didChangeConfiguration", {
		settings = yaml_client.config.settings,
	})
	vim.notify("Attached schema: " .. description, vim.log.levels.INFO)
end

-- TODO: add guards when accessing bufnr; check vim.api.nvim_buf_is_valid(bufnr)
-- first.

---Main logic: asynchronously parse YAML, match it against CRD or K8s resource,
---fetch schema, and cache it.
M.setup_buffer = async.void(function(bufnr)
	local ok, err = pcall(function()
		local buffer_content =
			table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
		local api_version, kind = M.extract_api_version_and_kind(buffer_content)
		local crd = nil
		if api_version and kind then
			crd = crds.match_crd(api_version, kind)
		end

		-- Depending on whether CRD is known or not, either fetch CRD schema or K8s
		-- resource schema
		if crd then
			local neg_key = "crd:" .. crd
			if not cache_mgmt.is_negative(neg_key) then
				local schema_url = crds.crd_schema_url .. "/" .. crd
				local abs, reason =
					cache_mgmt.ensure_local_schema(schema_url, vim.fs.joinpath("crds", crd))
				if abs then
					M.attach_schema(bufnr, abs, "CRD schema for " .. crd)
					vim.b[bufnr].schema_attached = true
				else
					if reason == "missing" then
						cache_mgmt.mark_negative(neg_key)
					end
					vim.notify(
						"No CRD schema found for " .. crd .. " due to " .. reason,
						vim.log.levels.WARN
					)
				end
			end
		else
			-- Check if the file is a Kubernetes YAML file
			if api_version and kind then
				-- Attach the Kubernetes schema
				local kubernetes_schema_url, reason =
					k8s.get_kubernetes_schema(api_version, kind)
				if kubernetes_schema_url then
					M.attach_schema(
						bufnr,
						kubernetes_schema_url,
						"Kubernetes schema for " .. kind
					)
					vim.b[bufnr].schema_attached = true
				elseif reason ~= "negative" then
					vim.notify(
						"No Kubernetes schema found for "
							.. kind
							.. " with apiVersion "
							.. api_version,
						vim.log.levels.WARN
					)
				end
			else
				-- Mark buffer to prevent it firing again
				vim.b[bufnr].schema_checked = true
				vim.notify(
					"No CRD or Kubernetes schema found. Falling back to default LSP configuration.",
					vim.log.levels.INFO
				)
			end
		end
	end)

	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.b[bufnr].schema_pending = false
	end

	if not ok then
		vim.notify("nvim-kube-schema: " .. tostring(err), vim.log.levels.WARN)
	end
end)

---Fetch YAML schema and attach it to the buffer, if yamlls is running.
---@param bufnr integer
M.init = function(bufnr)
	-- Check if the buffer has already been attached a schema, or resolved to
	-- "nothing to attach"
	if
		vim.b[bufnr].schema_attached
		or vim.b[bufnr].schema_pending
		or vim.b[bufnr].schema_checked
	then
		return
	end
	-- Mark the schema as attached; NOTE: this prevents retrying if any of the
	-- following fails
	vim.b[bufnr].schema_pending = true

	M.setup_buffer(bufnr)
end

return M
