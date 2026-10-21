--!strict
-- A page with a toolbar above it and a frosted menu over it. The page
-- posts messages back; the toolbar follows its title and history.
local PAGE = [[
<!doctype html>
<style>
  body { margin: 0; font: 15px -apple-system, sans-serif; color: #e8e6e1;
         background: linear-gradient(135deg, #3b2f63, #0f5e66 55%, #c46a2b); min-height: 100vh; }
  main { padding: 48px; }
  h1 { font-size: 44px; margin: 0 0 12px; }
  .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 14px; margin-top: 28px; }
  .grid div { height: 120px; border-radius: 14px; background: hsl(calc(var(--i) * 40), 70%, 60%); }
  button { font: inherit; padding: 8px 14px; border-radius: 8px; border: 0; }
</style>
<title>Local page</title>
<main>
  <h1>Hello from WebKit</h1>
  <p>The menu in the top right is zgui, drawn over this page with the system blur.</p>
  <button onclick="window.zgui.postMessage({ kind: 'clicked', at: Date.now() })">Send a message</button>
  <div class="grid">
    <div style="--i:0"></div><div style="--i:1"></div><div style="--i:2"></div><div style="--i:3"></div>
    <div style="--i:4"></div><div style="--i:5"></div><div style="--i:6"></div><div style="--i:7"></div>
  </div>
</main>
]]

local web = ui.web { profile = "ephemeral" }
local open = ui.state("open", false)
local messages = ui.state("messages", 0)

local function tool(label: string, on_click: () -> (), enabled: (() -> boolean)?)
	return ui.button {
		label,
		px = 10,
		h = 28,
		rounded = 7,
		text_size = 13,
		color = "#e8e6e1",
		bg = "#ffffff12",
		hover = { bg = "#ffffff22" },
		disabled = enabled and function()
			return not enabled()
		end or nil,
		on_click = on_click,
	}
end

-- Clear on the glass, lit on hover and keyboard focus.
local function item(label: string, on_click: () -> ())
	return ui.menu_item {
		label,
		h = 30,
		px = 10,
		rounded = 7,
		text_size = 13,
		color = "#e8e6e1",
		bg = "#00000000",
		hover = { bg = "#ffffff14" },
		focus = { bg = "#ffffff14", border = 0 },
		on_click = function()
			open:set(false)
			on_click()
		end,
	}
end

return ui.column {
	w_full = true,
	h_full = true,
	items = "stretch",
	bg = "#1b1a17",
	ui.row {
		items = "center",
		gap = 6,
		px = 10,
		h = 44,
		tool("‹", function()
			web:back()
		end, function()
			return web.can_go_back
		end),
		tool("›", function()
			web:forward()
		end, function()
			return web.can_go_forward
		end),
		tool("Reload", function()
			web:reload()
		end),
		ui.text {
			function()
				return web.loading and "Loading…" or web.title
			end,
			grow = 1,
			px = 8,
			text_size = 13,
			color = "#bdbab2",
			truncate = true,
		},
		ui.text { "{messages} messages", text_size = 12, color = "#8b887f" },
		ui.popover {
			open = open,
			anchor = ui.button {
				"Menu",
				px = 10,
				h = 28,
				rounded = 7,
				text_size = 13,
				color = "#e8e6e1",
				bg = "#ffffff12",
				on_click = ui.toggle(open),
			},
			w = 220,
			p = 6,
			gap = 2,
			rounded = 12,
			bg = "#2a2925a0",
			backdrop_blur = 24,
			border = 1,
			border_color = "#ffffff1f",
			shadow = { y = 12, blur = 32, color = "#00000066" },
			items = "stretch",
			item("Zoom 125%", function()
				web:zoom(1.25)
			end),
			item("Actual size", function()
				web:zoom(1)
			end),
			item("Turn the page", function()
				web:run("document.body.style.filter = 'hue-rotate(90deg)'")
			end),
			item("Web Inspector", function()
				web:devtools()
			end),
		},
	},
	ui.webview {
		web = web,
		html = PAGE,
		grow = 1,
		mx = 10,
		mb = 10,
		rounded = 12,
		on_message = function(value)
			if value.kind == "clicked" then
				messages:add(1)
			end
		end,
		on_error = function(_, err)
			print("page failed: " .. err)
		end,
	},
}
