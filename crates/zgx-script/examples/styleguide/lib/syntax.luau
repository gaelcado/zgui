-- Code's syntax colours, a line at a time, for zgx's `highlight` (the
-- editor's textarea, a reply's code block span): given a line and what the
-- line before left open, the line's spans (`{ from, to, colour }`, bytes
-- from 1) and what it leaves the next. zgx asks for each line once, and
-- again only for those that change. Zeron's languages (zeron-syntax's
-- Tree-sitter grammars) in its colours (theme.rs SyntaxPalette): keywords
-- and functions indigo, strings and constants emerald, numbers, types and
-- attributes amber, macros and tags pink, comments faint; a fence's or
-- file's language by its name or extension; anything else is plain.
--
-- States: 0 nothing open, 1 a block comment (`/*`, `--[[`, `<!--`).

local M = {}

-- Theme tokens, so a light or dark theme colours them its way.
local COMMENT = "$zeron.syntax.comment"
local KEYWORD = "$zeron.syntax.keyword"
local STRING = "$zeron.syntax.string"
local NUMBER = "$zeron.syntax.number"
local TYPE = "$zeron.syntax.type"
local FUNCTION = "$zeron.syntax.function"
local MACRO = "$zeron.syntax.macro"
local CONSTANT = "$zeron.syntax.constant"
local TAG = "$zeron.syntax.tag"
local ATTRIBUTE = "$zeron.syntax.number"

export type Span = { number | string }
export type Highlight = (line: string, state: number) -> ({ Span }, number)

local function set(words: string): { [string]: boolean }
	local out = {}
	for word in string.gmatch(words, "%S+") do
		out[word] = true
	end
	return out
end

type Language = {
	keywords: { [string]: boolean },
	-- Words that are values: true, nil, None.
	constants: { [string]: boolean }?,
	-- Line comments' openers, and a block comment's.
	line: { string },
	open: string?,
	close: string?,
	-- What opens a string.
	quotes: string,
	-- Capitalised words are types.
	types: boolean,
	-- Rust's `name!`.
	macros: boolean?,
	-- Markup: tags and their attributes.
	markup: boolean?,
}

local C_LIKE = "break case continue default do else for goto if return switch while"
local LANGUAGES: { [string]: Language } = {
	rust = {
		keywords = set([[as async await break const continue crate dyn else enum extern fn for if impl in
			let loop match mod move mut pub ref return self Self static struct super trait type unsafe use
			where while]]),
		constants = set("true false None Some Ok Err"),
		line = { "//" },
		open = "/*",
		close = "*/",
		quotes = '"',
		types = true,
		macros = true,
	},
	luau = {
		keywords = set([[and break continue do else elseif end export for function if in local not or
			repeat return then type typeof until while]]),
		constants = set("true false nil"),
		line = { "--" },
		open = "--[[",
		close = "]]",
		quotes = "\"'`",
		types = false,
	},
	toml = { keywords = set(""), constants = set("true false"), line = { "#" }, quotes = "\"'", types = false },
	javascript = {
		keywords = set([[async await break case catch class const continue debugger default delete do else
			export extends finally for from function if import in instanceof let new of return static super
			switch this throw try typeof var void while with yield as interface type enum implements
			declare readonly public private protected abstract namespace keyof]]),
		constants = set("true false null undefined NaN Infinity"),
		line = { "//" },
		open = "/*",
		close = "*/",
		quotes = "\"'`",
		types = true,
	},
	python = {
		keywords = set([[and as assert async await break class continue def del elif else except finally
			for from global if import in is lambda nonlocal not or pass raise return try while with
			yield match case]]),
		constants = set("True False None self cls"),
		line = { "#" },
		quotes = "\"'",
		types = true,
	},
	go = {
		keywords = set([[break case chan const continue default defer else fallthrough for func go goto
			if import interface map package range return select struct switch type var]]),
		constants = set("true false nil iota"),
		line = { "//" },
		open = "/*",
		close = "*/",
		quotes = "\"'`",
		types = true,
	},
	json = { keywords = set(""), constants = set("true false null"), line = {}, quotes = '"', types = false },
	bash = {
		keywords = set([[if then else elif fi case esac for select while until do done in function time
			return local export readonly declare unset shift exit source alias]]),
		constants = set("true false"),
		line = { "#" },
		quotes = "\"'",
		types = false,
	},
	c = {
		keywords = set(C_LIKE .. [[ auto char const double enum extern float inline int long register
			restrict short signed sizeof static struct typedef union unsigned void volatile bool
			#include #define #if #ifdef #ifndef #endif #else #pragma
			class namespace template typename public private protected virtual override new delete
			using operator friend explicit noexcept constexpr try catch throw this nullptr auto]]),
		constants = set("true false NULL nullptr"),
		line = { "//" },
		open = "/*",
		close = "*/",
		quotes = "\"'",
		types = true,
	},
	java = {
		keywords = set(C_LIKE .. [[ abstract assert boolean byte catch char class const double enum
			extends final finally float implements import instanceof int interface long native new
			package private protected public short static strictfp super synchronized this throw
			throws transient try void volatile var record sealed permits yield
			fun val when is object companion data override open internal lateinit init
			func let guard struct protocol extension import self Self inout where async await
			namespace using readonly ref out params get set event delegate]]),
		constants = set("true false null nil"),
		line = { "//" },
		open = "/*",
		close = "*/",
		quotes = "\"'",
		types = true,
	},
	ruby = {
		keywords = set([[alias and begin break case class def defined? do else elsif end ensure for if
			in module next not or redo rescue retry return self super then undef unless until when
			while yield require attr_accessor attr_reader]]),
		constants = set("true false nil"),
		line = { "#" },
		quotes = "\"'",
		types = true,
	},
	php = {
		keywords = set([[abstract and array as break case catch class clone const continue declare
			default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile
			extends final finally fn for foreach function global if implements include instanceof
			interface isset list match namespace new or print private protected public require return
			static switch throw trait try unset use var while yield]]),
		constants = set("true false null TRUE FALSE NULL"),
		line = { "//", "#" },
		open = "/*",
		close = "*/",
		quotes = "\"'",
		types = true,
	},
	sql = {
		keywords = set([[select from where and or not insert into values update set delete create table
			drop alter add index primary key foreign references join left right inner outer on as group
			by order having limit offset union all distinct case when then else end is in like between
			exists returning with SELECT FROM WHERE AND OR NOT INSERT INTO VALUES UPDATE SET DELETE CREATE
			TABLE DROP ALTER ADD INDEX PRIMARY KEY FOREIGN REFERENCES JOIN LEFT RIGHT INNER OUTER ON AS
			GROUP BY ORDER HAVING LIMIT OFFSET UNION ALL DISTINCT CASE WHEN THEN ELSE END IS IN LIKE
			BETWEEN EXISTS RETURNING WITH]]),
		constants = set("true false null TRUE FALSE NULL"),
		line = { "--" },
		open = "/*",
		close = "*/",
		quotes = "'\"",
		types = false,
	},
	yaml = {
		keywords = set(""),
		constants = set("true false null yes no"),
		line = { "#" },
		quotes = "\"'",
		types = false,
	},
	css = {
		keywords = set("@media @import @keyframes @font-face !important"),
		line = {},
		open = "/*",
		close = "*/",
		quotes = "\"'",
		types = false,
	},
	nix = {
		keywords = set("let in with rec inherit if then else assert import"),
		constants = set("true false null"),
		line = { "#" },
		open = "/*",
		close = "*/",
		quotes = '"',
		types = false,
	},
	make = {
		keywords = set("ifeq ifneq ifdef ifndef else endif include define endef export"),
		line = { "#" },
		quotes = "\"'",
		types = false,
	},
	dockerfile = {
		keywords = set([[FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG
			ONBUILD STOPSIGNAL HEALTHCHECK SHELL AS]]),
		line = { "#" },
		quotes = "\"'",
		types = false,
	},
	html = { keywords = set(""), line = {}, open = "<!--", close = "-->", quotes = "\"'", types = false, markup = true },
}

-- A fence's language, or a file's extension, to a language.
local NAMES: { [string]: string } = {
	rs = "rust",
	rust = "rust",
	luau = "luau",
	lua = "luau",
	toml = "toml",
	js = "javascript",
	jsx = "javascript",
	mjs = "javascript",
	cjs = "javascript",
	javascript = "javascript",
	ts = "javascript",
	tsx = "javascript",
	mts = "javascript",
	typescript = "javascript",
	py = "python",
	python = "python",
	go = "go",
	golang = "go",
	json = "json",
	jsonc = "json",
	json5 = "json",
	sh = "bash",
	bash = "bash",
	zsh = "bash",
	shell = "bash",
	console = "bash",
	c = "c",
	h = "c",
	cpp = "c",
	["c++"] = "c",
	cc = "c",
	cxx = "c",
	hpp = "c",
	java = "java",
	kt = "java",
	kotlin = "java",
	swift = "java",
	cs = "java",
	csharp = "java",
	["c#"] = "java",
	rb = "ruby",
	ruby = "ruby",
	php = "php",
	sql = "sql",
	yaml = "yaml",
	yml = "yaml",
	css = "css",
	scss = "css",
	nix = "nix",
	make = "make",
	makefile = "make",
	mk = "make",
	dockerfile = "dockerfile",
	containerfile = "dockerfile",
	html = "html",
	htm = "html",
	xml = "html",
	svg = "html",
	vue = "html",
}

local find, sub, byte = string.find, string.sub, string.byte

-- A quoted string from `from` (its opening quote): where it ends, or the
-- line's end if it runs on.
local function closing(line: string, from: number, quote: string): number
	local at = from + 1
	while true do
		local q = find(line, "[" .. quote .. "\\]", at)
		if not q then
			return #line
		end
		if byte(line, q) == 92 then
			at = q + 2
		else
			return q
		end
	end
end

-- Markup (HTML, XML, SVG): comments, tags pink, attributes amber, values
-- emerald.
local function markup(line: string, state: number): ({ Span }, number)
	local spans: { Span } = {}
	local at, n = 1, #line
	if state == 1 then
		local _, e = find(line, "-->", 1, true)
		if not e then
			return { { 1, n, COMMENT } }, 1
		end
		table.insert(spans, { 1, e, COMMENT })
		at = e + 1
	end
	while at <= n do
		local lt = find(line, "<", at, true)
		if not lt then
			break
		end
		if sub(line, lt, lt + 3) == "<!--" then
			local _, e = find(line, "-->", lt + 4, true)
			if not e then
				table.insert(spans, { lt, n, COMMENT })
				return spans, 1
			end
			table.insert(spans, { lt, e, COMMENT })
			at = e + 1
		else
			local s, e = find(line, "^/?[%w:%-_%.!]+", lt + 1)
			if s and e then
				table.insert(spans, { s, e, TAG })
				at = e + 1
				local stop = find(line, ">", at, true) or n
				while at < stop do
					local a1, a2 = find(line, "^%s*[%w:%-_@]+", at)
					if a1 and a2 and a2 < stop then
						local name = find(line, "[%w:%-_@]", a1) or a1
						table.insert(spans, { name, a2, ATTRIBUTE })
						at = a2 + 1
						local _, eq = find(line, "^%s*=%s*", at)
						if eq then
							at = eq + 1
							local q = sub(line, at, at)
							if q == '"' or q == "'" then
								local qe = closing(line, at, q)
								table.insert(spans, { at, qe, STRING })
								at = qe + 1
								if qe >= stop then
									stop = find(line, ">", at, true) or n
								end
							end
						end
					else
						at += 1
					end
				end
				at = stop + 1
			else
				at = lt + 1
			end
		end
	end
	return spans, 0
end

-- The highlighter for `language` (a `LANGUAGES` key).
local function tokenizer(language: string): Highlight
	local lang = LANGUAGES[language]
	if lang.markup then
		return markup
	end
	local quotes = lang.quotes
	local constants = lang.constants or {}
	return function(line: string, state: number): ({ Span }, number)
		local spans: { Span } = {}
		local at = 1
		local n = #line
		local open, close = lang.open, lang.close
		if state == 1 and close then
			local _, e = find(line, close, 1, true)
			if not e then
				return { { 1, n, COMMENT } }, 1
			end
			table.insert(spans, { 1, e, COMMENT })
			at = e + 1
		end
		while at <= n do
			local c = sub(line, at, at)
			local comment = false
			for _, marker in lang.line do
				if
					sub(line, at, at + #marker - 1) == marker and not (open and sub(line, at, at + #open - 1) == open)
				then
					comment = true
				end
			end
			if open and close and sub(line, at, at + #open - 1) == open then
				local _, e = find(line, close, at + #open, true)
				if not e then
					table.insert(spans, { at, n, COMMENT })
					return spans, 1
				end
				table.insert(spans, { at, e, COMMENT })
				at = e + 1
			elseif comment then
				table.insert(spans, { at, n, COMMENT })
				return spans, 0
			elseif find(quotes, c, 1, true) then
				local e = closing(line, at, c)
				table.insert(spans, { at, e, STRING })
				at = e + 1
			elseif find(c, "%d") then
				local _, e = find(line, "^[%w_%.]*", at)
				table.insert(spans, { at, e or at, NUMBER })
				at = (e or at) + 1
			elseif find(c, "[%a_@#$]") then
				local _, e = find(line, "^[%w_@#$%?]*", at)
				local stop = e or at
				local word = sub(line, at, stop)
				if lang.keywords[word] then
					table.insert(spans, { at, stop, KEYWORD })
				elseif constants[word] then
					table.insert(spans, { at, stop, CONSTANT })
				elseif lang.macros and sub(line, stop + 1, stop + 1) == "!" then
					table.insert(spans, { at, stop + 1, MACRO })
					stop += 1
				elseif find(line, "^%s*%(", stop + 1) then
					table.insert(spans, { at, stop, FUNCTION })
				elseif #word > 1 and find(word, "^[%u_][%u%d_]+$") then
					table.insert(spans, { at, stop, CONSTANT })
				elseif lang.types and find(word, "^%u") then
					table.insert(spans, { at, stop, TYPE })
				end
				at = stop + 1
			else
				at += 1
			end
		end
		return spans, 0
	end
end

local made: { [string]: Highlight } = {}

-- The highlighter for a language's name (a fence's `rust`, `ts`) or a
-- file's extension; nil for plain text. One per language, shared: zgx
-- keeps what it asked.
function M.for_language(name: string?): Highlight?
	local language = NAMES[string.lower(name or "")]
	if not language then
		return nil
	end
	local h = made[language]
	if not h then
		h = tokenizer(language)
		made[language] = h
	end
	return h
end

-- The highlighter for a file at `path`, by its extension (or its name: a
-- Makefile, a Dockerfile).
function M.for_path(path: string): Highlight?
	local name = string.match(path, "([^/]+)$") or path
	return M.for_language(string.match(name, "%.([%w_%+#]+)$") or name)
end

return M
