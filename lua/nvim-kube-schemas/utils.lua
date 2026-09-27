local M = {}

math.randomseed(os.time())

---Provides a random alphanumeric string of given length
---@param length integer
---@return string
M.random_string = function(length)
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890"
	local res = {}

	for i = 1, length do
		local ind = math.random(#chars)
		res[i] = chars:sub(ind, ind)
	end

	return table.concat(res)
end

---Trim whitespaces and escape sequences from right of input string
---@param s string
---@return string
M.trim_trailing = function(s)
	return s:match("^(.-)%s*$")
end

---Returns attached yamlls client given bufnr
---@param bufnr integer
---@return vim.lsp.Client?
M.get_yamlls_client = function(bufnr)
	local clients = vim.lsp.get_clients({ name = "yamlls", bufnr = bufnr })
	if #clients == 0 then
		vim.notify("yaml-language-server is not active.", vim.log.levels.WARN)
		return nil
	end
	return clients[1]
end

return M
