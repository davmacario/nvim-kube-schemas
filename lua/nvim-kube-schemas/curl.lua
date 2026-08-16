local curl = require("plenary.curl")
local async = require("plenary.async")
local async_util = require("plenary.async.util")

local M = {
	github_headers = {
		Accept = "application/vnd.github+json",
		["X-GitHub-Api-Version"] = "2022-11-28",
	},

	offline_until = nil, -- if set, we are offline until this timestamp
	offline_backoff = 60,  -- seconds
	request_timeout = 4000, -- ms
}

-- NOTE: async.wrap is used to create an async function
---Async implementation of 'get'
local curl_get_async = async.wrap(function(url, opts, callback)
	opts = vim.tbl_extend("force", opts or {}, {
		callback = function(res)
			callback(res)
		end,
		on_error = function(_)
			callback(nil)
		end,
	})
	curl.get(url, opts)
end, 3)

---Wraps plenary.curl.get to implement proper defaults and error handling.
---Returns the get result if successful, nil otherwise (including offline)
---@param url string
---@param extra table?
---@return table? res
M.http_get = function(url, extra)
	if M.offline_until and os.time() < M.offline_until then
		-- We are still offline
		return nil
	end

	local opts = vim.tbl_extend("force", { headers = M.github_headers, timeout = M.request_timeout }, extra or {})
	local ok, res = pcall(curl_get_async, url, opts)
	-- NOTE: used to avoid errors due to E5560 (nvim_echo gets invoked in fast
	-- event context by plenary callback)
	-- scheduler() forces the curl_get_async callback/on_error to be called on the
	-- next main loop iteration instead of right when curl exits
	async_util.scheduler()
	if not ok or type(res) ~= "table" or not res.status then
		M.offline_until = os.time() + M.offline_backoff
		return nil
	end
	M.offline_until = nil
	return res
end

return M
