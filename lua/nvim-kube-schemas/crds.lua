local cache_mgmt = require("nvim-kube-schemas.cache-management")
local curl = require("nvim-kube-schemas.curl")

local M = {
	github_base_api_url = "https://api.github.com/repos",
	crd_schemas_catalog = "datreeio/CRDs-catalog",
	crd_schema_catalog_branch = "main",
}
M.crd_schema_url = "https://raw.githubusercontent.com/"
	.. M.crd_schemas_catalog
	.. "/"
	.. M.crd_schema_catalog_branch

-- Schemas for the GitHub API response (CRD schema list):

---@class GitHubCRDListTreeEntry
---@field path string
---@field mode string
---@field type string
---@field sha string
---@field url string

---@class GitHubCRDListResponseBody
---@field sha string
---@field url string
---@field tree GitHubCRDListTreeEntry[]
---@field truncated boolean

---Download and cache the list of CRDs
---@return table<string, boolean>
M.list_github_tree = function()
	if cache_mgmt.cache.trees and next(cache_mgmt.cache.trees) ~= nil then
		return cache_mgmt.cache.trees
	end

	local cached, stat = cache_mgmt.read_cache_json(cache_mgmt.tree_cache_file_rel)
	-- Does not make sense to fill up a cache with nothing, so check # > 0
	if
		not cache_mgmt.is_stale(stat, cache_mgmt.tree_ttl)
		and cached
		and next(cached) ~= nil
	then
		cache_mgmt.cache.trees = cached
		return cached
	end

	-- Else, need to refresh cache
	local url = M.github_base_api_url
		.. "/"
		.. M.crd_schemas_catalog
		.. "/git/trees/"
		.. M.crd_schema_catalog_branch
	local response = curl.http_get(url, { query = { recursive = 1 } })

	-- Set: O(1) lookups given tree.path
	local trees = nil
	if response and response.status == 200 then
		---@type boolean, GitHubCRDListResponseBody
		local ok, body = pcall(vim.json.decode, response.body)
		if ok and type(body) == "table" and type(body.tree) == "table" then
			---@type table<string, boolean>
			trees = {}
			for _, tree in ipairs(body.tree) do
				if tree.type == "blob" and tree.path:match("%.json$") then
					trees[tree.path] = true
				end
			end
		end
	end

	if trees and next(trees) ~= nil then
		-- Only write content if non-empty
		cache_mgmt.write_cache(cache_mgmt.tree_cache_file_rel, vim.json.encode(trees))
	else
		trees = cached or {}
	end

	cache_mgmt.cache.trees = trees -- Cache the list of CRDs from GitHub API
	return trees
end

---Normalize apiVersion and kind to match CRD schema naming convention:
---			`<group>/<version>_<api_version>.json`
---@param api_version string
---@param kind string
---@return string?
M.normalize_crd_name = function(api_version, kind)
	if not api_version or not kind then
		return nil
	end
	-- Split apiVersion into group and version (e.g.,
	-- "argoproj.io/v1alpha1" -> "argoproj.io", "v1alpha1")
	local group, version = api_version:match("([^/]+)/([^/]+)")
	if not group or not version then
		return nil
	end
	-- Normalize kind to lowercase
	local normalized_kind = kind:lower()
	-- Construct the CRD name in the format: <group>/<kind>_<version>.json
	-- This is the expected name in the github repo
	return group .. "/" .. normalized_kind .. "_" .. version .. ".json"
end

---Match the CRD schema based on apiVersion and kind from the buffer contents.
---First, it normalizes the CRD name, and then matches it against a list of
---available schemas retrieved from the GitHub API.
---Only returns non-`nil` if a matching CRD is found in the list fetched from
---GitHub
---@param api_version string
---@param kind string
---@return string?
M.match_crd = function(api_version, kind)
	local crd_name = M.normalize_crd_name(api_version, kind)
	if not crd_name then
		return nil
	end
	local all_crds = M.list_github_tree()

	return all_crds[crd_name] and crd_name or nil
end

return M
