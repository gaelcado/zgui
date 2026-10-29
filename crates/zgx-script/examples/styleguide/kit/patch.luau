-- A unified diff (`git diff`'s output) read into files, hunks and lines, as
-- Zeron's changes view reads it (changes.rs parse_patch): each file's path
-- (its old one when renamed), whether it was added, deleted, renamed or is
-- binary, its counts, its notices and its hunks with every line's old and
-- new numbers.
local diff = require("./diff")

export type Status = "modified" | "added" | "deleted" | "renamed"
export type Hunk = { header: string, lines: { diff.Line } }
export type File = {
	path: string,
	old_path: string?,
	status: Status,
	binary: boolean,
	added: number,
	removed: number,
	hunks: { Hunk },
	-- What the patch said of it beyond its lines ("Mode changed to 100755").
	notices: { string },
}

local M = {}

function M.parse(patch: string): { File }
	local files: { File } = {}
	local file: File? = nil
	local hunk: Hunk? = nil
	local old, new = 0, 0
	for line in string.gmatch(patch, "([^\n]*)\n?") do
		local a, b = string.match(line, "^diff %-%-git a/(.-) b/(.*)$")
		if a then
			file = {
				path = b :: string,
				old_path = if a ~= b then a else nil,
				status = (if a ~= b then "renamed" else "modified") :: Status,
				binary = false,
				added = 0,
				removed = 0,
				hunks = {},
				notices = {},
			}
			table.insert(files, file :: File)
			hunk = nil
		elseif file then
			local f = file :: File
			if string.match(line, "^new file mode") then
				f.status = "added"
			elseif string.match(line, "^deleted file mode") then
				f.status = "deleted"
			elseif string.match(line, "^Binary files") or string.match(line, "^GIT binary patch") then
				f.binary = true
			elseif string.match(line, "^new mode ") and not hunk then
				table.insert(f.notices, `Mode changed to {string.sub(line, 10)}`)
			elseif string.match(line, "^@@") then
				local o, n = string.match(line, "^@@ %-(%d+)[^ ]* %+(%d+)")
				old, new = tonumber(o) or 0, tonumber(n) or 0
				hunk = { header = line, lines = {} }
				table.insert(f.hunks, hunk :: Hunk)
			elseif hunk and line ~= "" then
				local mark, text = string.sub(line, 1, 1), string.sub(line, 2)
				local h = hunk :: Hunk
				if mark == "+" then
					table.insert(h.lines, { kind = "add" :: diff.Kind, new = new, text = text })
					new += 1
					f.added += 1
				elseif mark == "-" then
					table.insert(h.lines, { kind = "del" :: diff.Kind, old = old, text = text })
					old += 1
					f.removed += 1
				elseif mark == " " then
					table.insert(h.lines, { kind = "ctx" :: diff.Kind, old = old, new = new, text = text })
					old += 1
					new += 1
				end
			end
		end
	end
	return files
end

-- A file's notice rows (changes.rs file_notices): new, deleted, renamed,
-- binary, then its own.
function M.notices(f: File): { string }
	local out: { string } = {}
	if f.status == "added" then
		table.insert(out, "New file")
	elseif f.status == "deleted" then
		table.insert(out, "Deleted file")
	elseif f.status == "renamed" then
		table.insert(out, `Renamed from {f.old_path or "?"}`)
	end
	if f.binary then
		table.insert(out, "Binary file — contents not shown")
	end
	table.move(f.notices, 1, #f.notices, #out + 1, out)
	return out
end

-- At most `max` of the hunks' lines in all (changes.rs truncate_file_lines),
-- and the notice saying so when lines were dropped: a tool row's diff is
-- built whole, so an edit rewriting a file is cut short.
function M.truncate(hunks: { Hunk }, max: number): ({ Hunk }, string?)
	local total = 0
	for _, h in hunks do
		total += #h.lines
	end
	if total <= max then
		return hunks, nil
	end
	local out: { Hunk } = {}
	local budget = max
	for _, h in hunks do
		if budget == 0 then
			break
		end
		local lines = if #h.lines > budget then table.move(h.lines, 1, budget, 1, {}) else h.lines
		budget -= #lines
		table.insert(out, { header = h.header, lines = lines })
	end
	return out, `Diff truncated — showing first {max} of {total} lines`
end

-- A hunk's lines paired for the split view (changes.rs split_pairs): a run
-- of deletions beside the run of additions after it, context beside itself.
export type Pair = { left: diff.Line?, right: diff.Line? }
function M.pairs(lines: { diff.Line }): { Pair }
	local out: { Pair } = {}
	local i = 1
	while i <= #lines do
		local l = lines[i]
		if l.kind == "ctx" then
			table.insert(out, { left = l, right = l })
			i += 1
		else
			local dels: { diff.Line }, adds: { diff.Line } = {}, {}
			while i <= #lines and lines[i].kind == "del" do
				table.insert(dels, lines[i])
				i += 1
			end
			while i <= #lines and lines[i].kind == "add" do
				table.insert(adds, lines[i])
				i += 1
			end
			for k = 1, math.max(#dels, #adds) do
				table.insert(out, { left = dels[k], right = adds[k] })
			end
		end
	end
	return out
end

return M
