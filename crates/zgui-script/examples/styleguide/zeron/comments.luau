-- Review comments (comments.rs): notes pinned to lines of a diff, staged on
-- a session's composer ("2 comments") and folded into its next prompt as
-- plain text, which the transcript reads back as a badge. No second model:
-- a comment is where it is (path, side, line) and what it says.
local M = {}

-- `side`: "L", a line of the original file (a deletion's number), or "R",
-- of the changed one.
export type Comment = { id: string, path: string, side: "L" | "R", line: number, body: string }

M.ONLY = "Address the review comments below."
M.HEADER =
	"Comments on the diff (each cites the file and line it belongs to; L = line number in the original file, R = in the changed file):"

-- The comments staged for session `key`'s next prompt.
function M.staged(key: string): State<{ Comment }>
	return ui.state(`{key}:comments`, {} :: { Comment })
end

-- "1 comment", "3 comments".
function M.label(n: number): string
	return if n == 1 then "1 comment" else `{n} comments`
end

-- `text` with the comments after it (with_comments): a bulleted block under
-- the header, each "path:line (side): body"; without text, the standing ask.
function M.fold(text: string, comments: { Comment }): string
	if #comments == 0 then
		return text
	end
	local bullets: { string } = {}
	for _, c in comments do
		local body = string.gsub(string.match(c.body, "^%s*(.-)%s*$") or c.body, "\n", "\n  ")
		table.insert(bullets, `- {c.path}:{c.line} ({c.side}): {body}`)
	end
	return `{if text == "" then M.ONLY else text}\n\n{M.HEADER}\n{table.concat(bullets, "\n")}`
end

-- The comments a prompt carries, read back (extract_badge): its text
-- before the block, and each comment's location, side and body; nil
-- without a block.
export type Read = { where: string, tag: string, body: string }
function M.read(text: string): (string, { Read }?)
	local marker = `\n\n{M.HEADER}\n`
	local at = string.find(text, marker, 1, true)
	if not at then
		return text, nil
	end
	local out: { Read } = {}
	for line in string.gmatch(string.sub(text, at + #marker), "[^\n]+") do
		local where, tag, body = string.match(line, "^%- (.-) %(([LR])%): (.*)$")
		if where then
			table.insert(out, { where = where, tag = tag :: string, body = body :: string })
		elseif #out > 0 and string.sub(line, 1, 2) == "  " then
			out[#out].body ..= "\n" .. string.sub(line, 3)
		end
	end
	return string.sub(text, 1, at - 1), if #out > 0 then out else nil
end

return M
