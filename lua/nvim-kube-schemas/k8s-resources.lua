local cache_mgmt = require("nvim-kube-schemas.cache-management")

local M = {
	k8s_resources_url = "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/refs/heads/master/master/",
}

---Get the correct Kubernetes schema URL (local) based on apiVersion and kind
---for built-in Kubernetes resources (non-CRD).
---Searches for the schema both with or without the version. Returns nil if no
---schema is found or if the resource matches an entry in the negative cache.
---Also returns a reason if url is nil: either "negative" (neg cache) or
---"missing"
---@param api_version string
---@param kind string
---@return string? url
---@return string? reason
M.get_kubernetes_schema = function(api_version, kind)
	local version = api_version:match("/([%w%-]+)$") or api_version
	local normalized_kind = kind:lower()

	local neg_key = "k8s:" .. normalized_kind .. "-" .. version
	if cache_mgmt.is_negative(neg_key) then
		return nil, "negative"
	end

	local name_with_version = normalized_kind .. "-" .. version .. ".json"
	local rel_with_version = vim.fs.joinpath("k8s", name_with_version)
	local url_with_version = M.k8s_resources_url .. name_with_version

	local abs, reason = cache_mgmt.ensure_local_schema(url_with_version, rel_with_version)
	if abs and abs ~= nil then
		return abs, nil
	end
	local with_missing = reason == "missing"

	local name_no_version = normalized_kind .. ".json"
	local rel_no_version = vim.fs.joinpath("k8s", name_no_version)
	local url_no_version = M.k8s_resources_url .. name_no_version

	abs, reason = cache_mgmt.ensure_local_schema(url_no_version, rel_no_version)
	if abs and abs ~= nil then
		return abs, nil
	end

	-- If both reasons are "missing", create negative hit cache.
	-- NOTE: if here, it means that also no CRDs matched
	if with_missing and reason == "missing" then
		cache_mgmt.mark_negative(neg_key)
	end

	-- If neither exists, return nil (yamlls will fallback to a default schema, if
	-- any)
	return nil, "missing"
end

return M
