-- Types the kit's props share, and the helpers that read them.
local M = {}

-- A condition a prop takes: a value, state or function (what the engine's
-- `disabled` takes).
export type Cond = boolean | Readable<boolean> | (() -> boolean)

-- `cond` now, tracked (for function properties).
function M.on(cond: Cond?): boolean
	if type(cond) == "boolean" then
		return cond
	elseif type(cond) == "function" then
		return cond()
	elseif cond ~= nil then
		-- A State (userdata) or anything else with `get`. `Readable`'s `get`
		-- takes `self: never` in the types (so a method call on it is the
		-- engine's to check), hence the cast.
		return (cond :: any):get() == true
	end
	return false
end

-- A condition's negation as a function, for `hidden` and the like.
function M.unless(cond: Cond?): () -> boolean
	return function()
		return not M.on(cond)
	end
end

-- Either of two conditions.
function M.either(a: Cond?, b: Cond?): () -> boolean
	return function()
		return M.on(a) or M.on(b)
	end
end

return M
