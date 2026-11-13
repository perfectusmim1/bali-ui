--[[
	Bali UI · Core/Services
	Lazy, cached service access. Uses cloneref when the executor provides it.
]]

local cloneref = (typeof(cloneref) == "function" and cloneref) or function(object)
	return object
end

local cache = {}

local Services = setmetatable({}, {
	__index = function(self, name)
		local service = cache[name]
		if service == nil then
			service = cloneref(game:GetService(name))
			cache[name] = service
		end
		return service
	end,
})

return Services
