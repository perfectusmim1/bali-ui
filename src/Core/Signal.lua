--[[
	Bali UI · Core/Signal
	Lightweight synchronous signal with safe handler execution.
]]

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handler = { Fn = fn, Connected = true }
	table.insert(self._handlers, handler)

	local connection = { Connected = true }
	function connection.Disconnect()
		if not handler.Connected then
			return
		end
		handler.Connected = false
		connection.Connected = false
		local index = table.find(self._handlers, handler)
		if index then
			table.remove(self._handlers, index)
		end
	end
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	-- copy so handlers can disconnect while firing
	local handlers = table.clone(self._handlers)
	for _, handler in ipairs(handlers) do
		if handler.Connected then
			local ok, err = pcall(handler.Fn, ...)
			if not ok then
				warn("[Bali] Signal handler error: " .. tostring(err))
			end
		end
	end
end

function Signal:Destroy()
	for _, handler in ipairs(self._handlers) do
		handler.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
