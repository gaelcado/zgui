-- Review comments (comments.rs): notes pinned to lines of a diff or of a
-- file's own text, staged on a session's composer ("2 comments") and
-- folded into its next prompt as plain text, which the transcript reads
-- back as a badge. No second model: a comment is where it is (path, side,
-- line) and what it says.
local M = {}

-- `side`: "L", a line of the original file (a deletion's number), or "R",
-- of the changed one; none for a line of the file as it is (Files). A
-- renamed file's `old_path`: where an "L" line lives (cite_path).
export type Comment = {
	id: string,
	path: string,
	side: ("L" | "R")?,
	line: number,
	body: string,
	old_path: string?,
}

M.ONLY = "Address the review comments below."
M.HEADER =
	"Comments on the diff (each cites the file and line it belongs to; L = line number in the original file, R = in the changed file):"
M.FILE_HEADER = "Review comments (each cites the workspace file and line it belongs to):"

-- The comments staged for session `key`'s next prompt.
function M.staged(key: string): State<{ Comment }>
	return ui.state(`{key}:comments`, {} :: { Comment })
end

-- The files whose edits session `key`'s next send waits for: a comment
-- on a file's line went with edits not yet saved, and an agent reading the
-- file must find that line where the comment says (begin_review_comment_flush).
function M.saving(key: string): State<{ [string]: boolean }>
	return ui.state(`{key}:comments_saving`, {} :: { [string]: boolean })
end
function M.held(key: string): boolean
	return next(M.saving(key):get()) ~= nil
end

-- The path its line is in (cite_path): an old side's line on a renamed
-- file lives in the file before the rename.
function M.cite(c: Comment): string
	return if c.side == "L" and c.old_path then c.old_path else c.path
end

-- "1 comment", "3 comments".
function M.label(n: number): string
	return if n == 1 then "1 comment" else `{n} comments`
end

-- `text` with the comments after it (with_comments): a bulleted block under
-- the header, each "path:line (side): body" ("path:line: body" for a
-- file's own line, which takes the files' header); without text, the
-- standing ask.
function M.fold(text: string, comments: { Comment }): string
	if #comments == 0 then
		return text
	end
	local bullets: { string } = {}
	local header = M.HEADER
	for _, c in comments do
		local body = string.gsub(string.match(c.body, "^%s*(.-)%s*$") or c.body, "\n", "\n  ")
		if c.side then
			table.insert(bullets, `- {M.cite(c)}:{c.line} ({c.side}): {body}`)
		else
			header = M.FILE_HEADER
			table.insert(bullets, `- {c.path}:{c.line}: {body}`)
		end
	end
	return `{if text == "" then M.ONLY else text}\n\n{header}\n{table.concat(bullets, "\n")}`
end

-- The comments a prompt carries, read back (extract_badge): its text
-- before the block, and each comment's location, side (none for a file's
-- line) and body; nil without a block.
export type Read = { where: string, tag: string?, body: string }
function M.read(text: string): (string, { Read }?)
	local at, marker = nil, ""
	for _, header in { M.HEADER, M.FILE_HEADER } do
		marker = `\n\n{header}\n`
		at = string.find(text, marker, 1, true)
		if at then
			break
		end
	end
	if not at then
		return text, nil
	end
	local out: { Read } = {}
	for line in string.gmatch(string.sub(text, at + #marker), "[^\n]+") do
		local where, tag, body = string.match(line, "^%- (.-) %(([LR])%): (.*)$")
		if not where then
			where, body = string.match(line, "^%- (%S-:%d+): (.*)$")
			tag = nil
		end
		if where then
			table.insert(out, { where = where, tag = tag, body = body :: string })
		elseif #out > 0 and string.sub(line, 1, 2) == "  " then
			out[#out].body ..= "\n" .. string.sub(line, 3)
		end
	end
	return string.sub(text, 1, at - 1), if #out > 0 then out else nil
end

return M
