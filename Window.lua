local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Window = {}
ns.Window = Window

local frame
local state = { query = "", stack = {} }

local COLUMNS = {
	{ key = "name", label = "Name", width = 170 },
	{ key = "level", label = "Level", width = 60 },
	{ key = "money", label = "Gold", width = 130 },
	{ key = "rested", label = "Rested", width = 80 },
	{ key = "ilvl", label = "Gear", width = 60 },
	{ key = "zone", label = "Zone", width = 170 },
	{ key = "seen", label = "Last seen", width = 100 },
}

local STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

local function classColor(class)
	local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return C.text[1], C.text[2], C.text[3]
end

local function restedPercent(c)
	if not c.xpMax or c.xpMax <= 0 then return 0 end
	return math.floor(ns.Rested(c) / c.xpMax * 100 + 0.5)
end

local function value(c, key)
	if key == "name" then return (c.name or ""):lower() end
	if key == "zone" then return (c.zone or ""):lower() end
	if key == "rested" then return restedPercent(c) end
	return c[key] or 0
end

local function overview()
	local list = ns.All()
	local key, desc = ns.db.sort, ns.db.desc
	table.sort(list, function(a, b)
		local x, y = value(a, key), value(b, key)
		if x ~= y then
			if desc then return x > y end
			return x < y
		end
		if a.name ~= b.name then return a.name < b.name end
		return a.realm < b.realm
	end)
	local rows = {}
	for _, c in ipairs(list) do rows[#rows + 1] = { kind = "char", char = c } end
	if #rows == 0 then rows[1] = { kind = "note", text = "No characters recorded yet." } end
	return rows
end

local function totals()
	local sums, order, all = {}, {}, 0
	for _, c in ipairs(ns.All()) do
		local key = c.realm .. "  " .. (c.faction or "")
		if not sums[key] then
			sums[key] = 0
			order[#order + 1] = key
		end
		sums[key] = sums[key] + (c.money or 0)
		all = all + (c.money or 0)
	end
	table.sort(order)
	local parts = {}
	for _, key in ipairs(order) do parts[#parts + 1] = key .. ": " .. ACore.Money(sums[key]) end
	if #order > 1 then parts[#parts + 1] = "All: " .. ACore.Money(all) end
	return table.concat(parts, "     ")
end

local function note(rows, text, dim)
	rows[#rows + 1] = { kind = "note", text = text, dim = dim }
end

local function detail(c)
	local rows = {}
	rows[#rows + 1] = { kind = "header", text = "Character" }
	local line = "Level " .. (c.level or "?") .. " " .. (c.race or "") .. " " .. ns.ClassName(c.class)
	if c.guild then line = line .. "   <" .. c.guild .. ">" .. (c.guildRank and ("  " .. c.guildRank) or "") end
	note(rows, line)
	if c.note then note(rows, "Note: " .. c.note) end
	local today = ""
	if c.dayStart and c.day == (date and date("%Y-%m-%d")) and c.money and c.money ~= c.dayStart then
		local diff = c.money - c.dayStart
		today = "  (" .. (diff > 0 and "+" or "-") .. ACore.Money(math.abs(diff)) .. " today)"
	end
	note(rows, "Gold: " .. ACore.Money(c.money or 0) .. today .. "      Zone: " .. (c.zone or "unknown") .. "      Seen: " .. ns.Ago(c.seen))
	if c.xpMax and c.xpMax > 0 and not c.capped then
		note(rows, string.format("Experience: %s / %s (%d%%)      Rested: %s%d%%%s", ACore.Short(c.xp or 0), ACore.Short(c.xpMax),
			math.floor((c.xp or 0) / c.xpMax * 100), ns.IsCurrent(c) and "" or "about ", restedPercent(c), c.resting and "  (resting)" or ""))
	end
	if c.played then
		note(rows, "Played: " .. ns.Duration(c.played) .. (c.playedLevel and ("      This level: " .. ns.Duration(c.playedLevel)) or ""))
	end
	if c.rank then note(rows, "Rank: " .. c.rank.name .. " (" .. c.rank.number .. ")") end
	local space = "Bags: " .. (c.bagFree or 0) .. " free of " .. (c.bagTotal or 0)
	if c.bankTotal then space = space .. "      Bank: " .. c.bankFree .. " free of " .. c.bankTotal end
	note(rows, space)
	if c.mailSeen then
		local expire = ""
		if c.mailExpire and (c.mail or 0) > 0 then
			local left = c.mailExpire - ns.Now()
			expire = left > 0 and ("      First expires in " .. ns.Duration(left)) or "      Some may have expired"
		end
		note(rows, "Mail: " .. (c.mail or 0) .. " in the box " .. ns.Ago(c.mailSeen) .. expire)
	elseif c.newMail then
		note(rows, "Mail: new mail waiting")
	end

	if c.profs and #c.profs > 0 then
		rows[#rows + 1] = { kind = "header", text = "Professions" }
		for _, p in ipairs(c.profs) do
			rows[#rows + 1] = { kind = "pair", text = p.name, right = p.rank .. " / " .. p.max, dim = not p.main }
		end
	end
	if c.cooldowns and #c.cooldowns > 0 then
		rows[#rows + 1] = { kind = "header", text = "Cooldowns" }
		for _, cd in ipairs(c.cooldowns) do
			local left = cd.ready - ns.Now()
			rows[#rows + 1] = { kind = "pair", text = cd.name, right = left > 0 and ("ready in " .. ns.Duration(left)) or "ready", good = left <= 0 }
		end
	end
	if c.lockouts then
		local any = false
		for _, l in ipairs(c.lockouts) do
			local left = l.reset - ns.Now()
			if left > 0 then
				if not any then
					rows[#rows + 1] = { kind = "header", text = "Instance lockouts" }
					any = true
				end
				rows[#rows + 1] = { kind = "pair", text = l.name .. (l.diff and ("  " .. l.diff) or ""), right = "resets in " .. ns.Duration(left) }
			end
		end
	end
	if c.gear and next(c.gear) then
		rows[#rows + 1] = { kind = "header", text = "Gear" .. ((c.ilvl or 0) > 0 and ("  (average item level " .. c.ilvl .. ")") or "") }
		for _, s in ipairs(ns.SLOTS) do
			local link = c.gear[s[1]]
			if link then rows[#rows + 1] = { kind = "gear", text = link, right = s[2], link = link } end
		end
	end
	if c.reps and #c.reps > 0 then
		rows[#rows + 1] = { kind = "header", text = "Reputations" }
		for _, r in ipairs(c.reps) do
			local right = STANDING[r.standing] or ""
			if r.max and r.max > 0 then right = right .. "  " .. r.value .. " / " .. r.max end
			rows[#rows + 1] = { kind = "pair", text = r.name, right = right, dim = r.standing <= 4 }
		end
	end
	return rows
end

function ns.ClassName(class)
	if not class then return "" end
	local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
	if n then return n end
	return class:sub(1, 1) .. class:sub(2):lower()
end

local function itemRows()
	if not ns.HasBags() then
		return { { kind = "note", text = "Item search needs ABag, which stores what each character carries." } }
	end
	local rows = ns.FindItems(state.query)
	if #rows == 0 then rows[1] = { kind = "note", text = "Nobody has that." } end
	return rows
end

local function createRow(list)
	local row = CreateFrame("Button", nil, list)
	row.hl = UI.Fill(row, C.hover, "HIGHLIGHT")
	row.band = UI.Fill(row, { 1, 1, 1, 0.05 })
	row.cells = {}
	local x = 10
	for i, col in ipairs(COLUMNS) do
		local fs = UI.Text(row, "GameFontHighlightSmall")
		fs:SetPoint("LEFT", x, 0)
		fs:SetWidth(col.width - 8)
		row.cells[i] = fs
		x = x + col.width
	end
	row.right = UI.Text(row, "GameFontHighlightSmall", "RIGHT", C.dim)
	row.right:SetPoint("RIGHT", -10, 0)
	row.text = UI.Text(row, "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 10, 0)
	row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button)
		local d = self.data
		if not d then return end
		if d.kind == "char" then
			local c = d.char
			if button == "RightButton" then
				UI.Menu(self, {
					{ text = c.name, title = true },
					{ text = "Open", func = function() Window.ShowChar(c) end },
					{ text = c.note and "Change note" or "Add note", func = function()
						UI.Prompt("Note for " .. c.name, c.note or "", function(text)
							text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
							c.note = text ~= "" and text or nil
							ns:Fire("CHARS_CHANGED")
						end)
					end },
					{ text = "Delete this entry", func = function()
						UI.Confirm("Remove " .. c.name .. " from AAlts?", function() ns.Delete(c) end)
					end },
				})
			else
				Window.ShowChar(c)
			end
		elseif (d.kind == "gear" or d.kind == "item") and d.link and IsShiftKeyDown and IsShiftKeyDown() then
			if ChatEdit_InsertLink then ChatEdit_InsertLink(d.link) end
		end
	end)
	row:SetScript("OnEnter", function(self)
		local d = self.data
		if not d then return end
		if d.kind == "gear" or (d.kind == "item" and d.link) then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			pcall(GameTooltip.SetHyperlink, GameTooltip, d.link)
			GameTooltip:Show()
		elseif d.kind == "item" then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, d.id) end
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function color(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

local function updateRow(row, d)
	row.band:SetShown(d.kind == "header")
	row.hl:SetShown(d.kind == "char" or d.kind == "gear" or d.kind == "item")
	local isChar = d.kind == "char"
	for _, fs in ipairs(row.cells) do fs:SetShown(isChar) end
	row.text:SetShown(not isChar)
	row.right:SetShown(not isChar)
	if isChar then
		local c = d.char
		local cells = row.cells
		cells[1]:SetText(c.name .. (c.realm ~= ns.Realm() and (" - " .. c.realm) or "") .. (ns.IsCurrent(c) and " *" or ""))
		cells[1]:SetTextColor(classColor(c.class))
		cells[2]:SetText(c.level or "?")
		cells[3]:SetText(ACore.Money(c.money or 0))
		local rested = restedPercent(c)
		cells[4]:SetText(rested > 0 and (rested .. "%") or "-")
		color(cells[4], rested > 0 and { 0.35, 0.65, 1 } or C.dim)
		cells[5]:SetText((c.ilvl or 0) > 0 and c.ilvl or "-")
		cells[6]:SetText(c.zone or "")
		cells[7]:SetText(ns.Ago(c.seen))
		color(cells[7], C.dim)
		return
	end
	row.right:SetText(d.right or "")
	if d.kind == "header" then
		row.text:SetText(d.text)
		color(row.text, C.accent)
	elseif d.kind == "item" then
		local parts = {}
		for _, o in ipairs(d.owners) do parts[#parts + 1] = ns.OwnerText(o) end
		row.text:SetText(d.link or d.name)
		color(row.text, C.text)
		row.right:SetText(table.concat(parts, ", "))
	else
		row.text:SetText(d.text or "")
		if d.good then
			row.text:SetTextColor(0.35, 0.8, 0.35)
		elseif d.dim then
			color(row.text, C.dim)
		else
			color(row.text, C.text)
		end
	end
end

local function build()
	frame = UI.Window("AAltsFrame", "AAlts", 800, 500, ns.db.window)
	local bar = frame.bar

	local search = UI.EditBox(bar, "Who has this item", function(text)
		ns.Debounce("search", 0.2, function()
			local q = text:gsub("^%s+", ""):gsub("%s+$", "")
			if q == state.query then return end
			state.query = q
			state.stack = {}
			Window.Refresh()
		end)
	end)
	search:SetPoint("LEFT", 100, 0)
	search:SetWidth(260)
	frame.search = search

	local options = UI.Button(bar, "Options", function(self) UI.Menu(self, ns.Options()) end)
	options:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)

	local body = frame.body
	local head = CreateFrame("Frame", nil, body)
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(26)
	UI.Fill(head, { 0.075, 0.08, 0.1, 1 })
	frame.head = head

	local back = UI.Button(head, "< Back", function()
		table.remove(state.stack)
		Window.Refresh()
	end)
	back:SetPoint("LEFT", 8, 0)
	frame.back = back
	frame.viewTitle = UI.Text(head, "GameFontNormal", "LEFT", C.text)
	frame.viewTitle:SetPoint("LEFT", back, "RIGHT", 10, 0)

	frame.sorters = {}
	local x = 6
	for i, col in ipairs(COLUMNS) do
		local b = UI.Button(head, col.label, function()
			if ns.db.sort == col.key then
				ns.db.desc = not ns.db.desc
			else
				ns.db.sort = col.key
				ns.db.desc = col.key ~= "name" and col.key ~= "zone"
			end
			Window.Refresh()
		end)
		b:SetHeight(20)
		b:SetPoint("LEFT", x, 0)
		b.key = col.key
		b.base = col.label
		frame.sorters[i] = b
		x = x + col.width
	end

	local foot = CreateFrame("Frame", nil, body)
	foot:SetPoint("BOTTOMLEFT")
	foot:SetPoint("BOTTOMRIGHT")
	foot:SetHeight(24)
	UI.Fill(foot, C.bar)
	frame.totals = UI.Text(foot, "GameFontHighlightSmall", "LEFT", C.dim)
	frame.totals:SetPoint("LEFT", 10, 0)
	frame.totals:SetPoint("RIGHT", -10, 0)

	local list = UI.List(body, 22, createRow, updateRow)
	list:SetPoint("TOPLEFT", 0, -28)
	list:SetPoint("BOTTOMRIGHT", 0, 26)
	frame.list = list
end

function Window.Refresh()
	if not frame or not frame:IsShown() then return end
	local top = state.stack[#state.stack]
	local rows, title, mode
	if top then
		rows = detail(top)
		title = top.name .. "  -  " .. top.realm
		mode = "detail"
	elseif state.query ~= "" then
		rows = itemRows()
		title = "Items matching: " .. state.query
		mode = "items"
	else
		rows = overview()
		mode = "overview"
	end
	frame.back:SetShown(top ~= nil)
	frame.viewTitle:ClearAllPoints()
	if top then
		frame.viewTitle:SetPoint("LEFT", frame.back, "RIGHT", 10, 0)
	else
		frame.viewTitle:SetPoint("LEFT", 10, 0)
	end
	frame.viewTitle:SetText(title or "")
	frame.viewTitle:SetShown(mode ~= "overview")
	for _, b in ipairs(frame.sorters) do
		b:SetShown(mode == "overview")
		local on = ns.db.sort == b.key
		b:SetLabel(b.base .. (on and (ns.db.desc and " v" or " ^") or ""))
		b:SetActive(on)
	end
	frame.totals:SetText(totals())
	frame.list:SetData(rows, frame.mode == mode and frame.top == top)
	frame.mode, frame.top = mode, top
end

function Window.Show()
	if not frame then build() end
	if ns.ScanAll then pcall(ns.ScanAll) end
	frame:Show()
	Window.Refresh()
end

function Window.Hide()
	if frame then frame:Hide() end
end

function Window.Toggle()
	if frame and frame:IsShown() then
		Window.Hide()
	else
		Window.Show()
	end
end

function Window.ShowChar(c)
	Window.Show()
	state.stack = { c }
	Window.Refresh()
end

function Window.SetSearch(text)
	if not frame then return end
	frame.search.box:SetText(text or "")
end

ns:Listen("CHARS_CHANGED", function()
	local top = state.stack[#state.stack]
	if top and not (ns.db.chars[top.realm] and ns.db.chars[top.realm][top.name]) then state.stack = {} end
	Window.Refresh()
end)
ns:On("GET_ITEM_INFO_RECEIVED", function()
	if frame and frame.mode == "items" and frame:IsShown() then ns.Debounce("items", 0.5, Window.Refresh) end
end)
ns:Listen("LAYOUT_RESET", function()
	if frame then frame:Restore() end
end)
