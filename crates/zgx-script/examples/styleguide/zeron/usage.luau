-- The account's usage in the composer (account_usage.rs): the session's
-- harness's live account and how much of its plan it has used, beside the
-- context's ring; its card lists the harness's accounts, and choosing
-- another switches to it (as Settings → Accounts does), at once.
local kit = require("@kit")
local data = require("./data")

local M = {}

-- Each harness's accounts, as the engine would send them.
M.accounts = ui.state("z_accounts", data.ACCOUNTS)

-- Switches `harness` to account `id`: its row is in use, the others not.
function M.switch(harness: string, id: string)
	local all = table.clone(M.accounts:peek())
	local list: { data.Account } = {}
	for _, a in all[harness] or {} do
		local copy = table.clone(a)
		copy.active = a.id == id
		table.insert(list, copy)
	end
	all[harness] = list
	M.accounts:set(all)
end

-- The ring for a session on `harness`, its ids under `id`; nil where the
-- harness reports no usage.
function M.chip(harness: string, id: string): Node?
	local listed = data.ACCOUNTS[harness]
	if not listed or kit.context_usage.used(listed) == nil then
		return nil
	end
	return kit.context_usage.account {
		id = id,
		provider = data.PROVIDERS[harness] or "Agent",
		accounts = ui.computed(function(): { data.Account }
			return M.accounts:get()[harness] or {}
		end),
		on_switch = function(account: string)
			M.switch(harness, account)
		end,
	}
end

return M
