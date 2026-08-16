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

return M
