--[[
	ModuleScript — shared, part of the modular system architecture.

	Studio placement:
		ReplicatedStorage > Shared > Signal (ModuleScript)

	Purpose:
		Lightweight pub/sub event object. This is the cross-system
		communication layer called out in the project architecture rules —
		systems (BoardService, MovementService, CardService, etc.) fire and
		listen on Signal instances instead of calling into each other's
		internals directly. Any script on either the server or the client
		can require this module.

	Usage:
		local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)

		local TileOwnerChanged = Signal.new()

		local connection = TileOwnerChanged:Connect(function(tileId, newOwner)
			print(tileId, newOwner)
		end)

		TileOwnerChanged:Fire(3, somePlayer)

		connection:Disconnect()
]]

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_handlers = {},
		_nextId = 1,
	}, Signal)
end

function Signal:Connect(fn)
	local id = self._nextId
	self._nextId += 1
	self._handlers[id] = fn

	local connection = {}
	function connection.Disconnect()
		self._handlers[id] = nil
	end

	return connection
end

function Signal:Fire(...)
	for _, fn in pairs(self._handlers) do
		task.spawn(fn, ...)
	end
end

function Signal:DisconnectAll()
	self._handlers = {}
end

return Signal
