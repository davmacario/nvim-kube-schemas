local async = require("plenary.async")
local cache_mgmt = require("nvim-kube-schemas.cache-management")
local crds = require("nvim-kube-schemas.crds")
local k8s = require("nvim-kube-schemas.k8s-resources")
local utils = require("nvim-kube-schemas.utils")

local M = {}

---Extract apiVersion and kind from YAML file content
---@param buffer_content string
---@return string?
---@return string?
M.extract_api_version_and_kind = function(buffer_content)
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
	-- Buffer file name
	local pattern = vim.api.nvim_buf_get_name(bufnr)
	local yaml_client = utils.get_yamlls_client(bufnr)
	if yaml_client == nil then
		return
	end

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

---Main logic: asynchronously parse YAML, match it against CRD or K8s resource,
---fetch schema, and cache it.
---Sets the following buffer options:
---  - vim.b[bufnr].schema_checked: true right after all documents in the buffer have
---		 been checked for their schema. Doesn't tell anything about success
---  - vim.b[bufnr].schema_attached: true if any schema was attached
M.setup_buffer = async.void(function(bufnr)
	local ok, err = pcall(function()
		-- Store the schemas attached so far (`<api>/<version>`); it is a set (keyed by
		-- schema string)
		-- Also caches negative hits (i.e., no schema found)
		-- NOTE: this cache only works within the same buffer
		local seen_schemas = {}

		-- List of all the documents (as strings, with '\n')
		local buffer_content = {}
		-- List of lines in current document; will be concatenated once over
		local curr_doc = {}
		for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
			local line_trim = utils.trim_trailing(line)
			if line_trim:match("^%-%-%-$") or line_trim:match("^%-%-%-%s") then
				if next(curr_doc) ~= nil then
					-- New document complete
					buffer_content[#buffer_content + 1] = table.concat(curr_doc, "\n")
					curr_doc = {}
				end
			else
				curr_doc[#curr_doc + 1] = line_trim
			end
		end

		if next(curr_doc) ~= nil then
			buffer_content[#buffer_content + 1] = table.concat(curr_doc, "\n")
		end

		for _, doc in ipairs(buffer_content) do
			local api_version, kind = M.extract_api_version_and_kind(doc)

			-- If not a k8s resource, skip current doc
			if api_version and kind then
				local crd = crds.match_crd(api_version, kind)

				local curr_schema = api_version .. "/" .. kind

				if seen_schemas[curr_schema] == nil then
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
					end
					seen_schemas[curr_schema] = true
				end
			end
		end
		-- Mark buffer to prevent it firing again, only when every doc succeeded
		vim.b[bufnr].schema_checked = true
	end)

	if vim.api.nvim_buf_is_valid(bufnr) then
		if not vim.b[bufnr].schema_attached then
			vim.notify(
				"No CRD or Kubernetes schema found for any document. "
					.. "Falling back to default LSP configuration.",
				vim.log.levels.INFO
			)
		end

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
