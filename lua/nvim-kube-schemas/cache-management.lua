local curl = require("nvim-kube-schemas.curl")
local utils = require("nvim-kube-schemas.utils")

local M = {
	---Root folder of cache (can be overridden TODO)
	cache_root = vim.fs.joinpath(vim.fn.stdpath("data"), "yaml-schemas"),

	---File name (relative to data dir) containing cached CRD list
	tree_cache_file_rel = "crd-tree.json",

	---TTL for the cache of the CRD list (1 day)
	tree_ttl = 86400,

	---@alias StringSet table<string, true>

	---@class Cache
	---@field trees StringSet
	---@field meta Meta
	cache = {}, --Local in-memory cache

	--Metadata management
	meta_cache_file_rel = "meta.json",
	meta_ttl = 604800, -- 7 days
}

---Turn a relative key of a schema file into an absolute path using
---`M.cache_root`
---@param rel string
---@return string?
M.cache_path = function(rel)
	if rel:find("%.%.") then
		-- Reject dangerous `..` in the path
		return nil
	end
	return vim.fs.joinpath(M.cache_root, rel)
end

---Given a path of a schema, evaluated from the current buffer contents, look it
---up in the cache, and, if found, return:
--- - the file contents (as string)
--- - the stat of the file
---@param rel string
---@return string?
---@return uv.fs_stat.result?
M.read_cache = function(rel)
	local path = M.cache_path(rel)
	if not path then
		return nil, nil
	end
	local stat = vim.uv.fs_stat(path)
	-- Valid JSON (schema) is at least 2 bytes long (`{}`). Reject if not
	if not stat or stat.size < 2 or stat.type ~= "file" then
		-- Rejected truncated
		return nil, nil
	end
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return nil, nil
	end
	return table.concat(lines, "\n"), stat
end

---Given a path of a JSON schema, evaluated from buffer contents, look it up in
---the cache and, if found, return:
--- - JSON file contents decoded to a table
--- - stat of file
---@param rel string
---@return table?
---@return uv.fs_stat.result?
M.read_cache_json = function(rel)
	local content, stat = M.read_cache(rel)
	if not content or not stat then
		return nil, nil
	end
	local ok, json_table = pcall(vim.json.decode, content)
	if not ok then
		return nil, stat
	end
	return json_table, stat
end

---Populate cache entry (single schema) for `rel` by writing `body` into it.
---Performs atomic write (write + rename) to avoid corruption.
---Returns true if the write operation was correct, false if anything fails.
---@param rel string
---@param body string
---@return boolean
M.write_cache = function(rel, body)
	local abs_path = M.cache_path(rel)
	if not abs_path then
		return false
	end
	local dir_name = vim.fs.dirname(abs_path)
	vim.fn.mkdir(dir_name, "p")
	local tmp_path = abs_path .. "." .. utils.random_string(6) .. ".tmp"
	local write_res = vim.fn.writefile(vim.fn.split(body, "\n"), tmp_path)
	if write_res ~= 0 then
		return false
	end
	return vim.uv.fs_rename(tmp_path, abs_path) or false
end
-- TODO: finalize interrupted writes (look for .tmp files) on startup

---Returns true if the stat is nil or if the file is older than ttl (seconds)
---@param stat uv.fs_stat.result?
---@param ttl integer
---@return boolean
M.is_stale = function(stat, ttl)
	-- stat.mtime
	if not stat then
		return true
	end
	return (os.time() - stat.mtime.sec) >= ttl
end

---Ensure that the requested schema (URL) is cached locally at `rel`.
---Returns the absolute path of the schema (to be passed to yamlls) and a reason
---string indicating the failure (if any).
---Failure reasons: "path_error" (path contains `..`), "offline", "missing",
---"write_failed"
---@param url string
---@param rel string
---@return string? abs
---@return string? reason
M.ensure_local_schema = function(url, rel)
	local abs = M.cache_path(rel)
	if not abs then
		return nil, "path_error"
	end

	local stat = vim.uv.fs_stat(abs)
	if stat and stat.size >= 2 and stat.type == "file" then
		return abs, nil
	end

	local res = curl.http_get(url)
	if res == nil then
		return nil, "offline"
	end
	if res.status ~= 200 then
		return nil, "missing"
	end
	local ok, _ = pcall(vim.json.decode, res.body)
	if not ok then
		return nil, "missing"
	end

	if M.write_cache(rel, res.body) then
		return abs, nil
	end
	return nil, "write_failed"
end

---Models contents of metadata
---@class Meta
---@field negative table Contains entries of negative cache in format <key> -> <ts>

---Load metadata from file (meta.json) into local map
---@return Meta meta
M.load_meta = function()
	if M.cache.meta and M.cache.meta ~= nil then
		return M.cache.meta
	end
	local meta = M.read_cache_json(M.meta_cache_file_rel)
	if type(meta) ~= "table" then
		meta = {}
	end
	meta.negative = meta.negative or {}
	M.cache.meta = meta
	return meta
end

---Write current contents of meta cache to file
M.save_meta = function()
	M.write_cache(M.meta_cache_file_rel, vim.json.encode(M.load_meta()))
end

---Returns true if the provided key matches a valid entry in the negative cache
---@param key string
---@return boolean
M.is_negative = function(key)
	local ts = M.load_meta().negative[key]
	if not ts then
		return false
	end
	-- If negative entry is younger than ttl, cache hits
	return (os.time() - ts) <= M.meta_ttl
end

---Marks the given `key` as negative cache
---@param key string
M.mark_negative = function(key)
	M.load_meta().negative[key] = os.time()
	M.save_meta()
end

return M
