--[[
	Lumina UI · Core/Maid
	Tracks connections, instances, callbacks and objects for deterministic cleanup.
]]

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _items = {} }, Maid)
end

function Maid:Give(item)
	if item ~= nil then
		table.insert(self._items, item)
	end
	return item
end

local function cleanup(item)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		pcall(task.cancel, item)
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item.Disconnect()
		end
	end
end

function Maid:Clean()
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		local ok, err = pcall(cleanup, items[index])
		if not ok then
			warn("[Lumina] Cleanup error: " .. tostring(err))
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid
