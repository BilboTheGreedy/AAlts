local ADDON, ns = ...

local defaults = {
	chars = {},
	window = { scale = 1 },
	played = true,
	tooltip = true,
	sort = "name",
	desc = false,
}

ACore.New(ADDON, ns, { db = "AAltsDB", defaults = defaults, profile = true, shared = { "chars" } })

ACore.Register({
	name = "AAlts",
	options = function() return ns.Options() end,
	title = "AAlts",
	slash = "/aalts",
	desc = "all your characters",
	toggle = function() ns.Window.Toggle() end,
})

function ns.Now()
	return time and time() or 0
end

function ns.Realm()
	local realm = GetRealmName and GetRealmName() or "Realm"
	if type(realm) ~= "string" or realm == "" then realm = "Realm" end
	return realm
end

function ns.Name()
	local name = UnitName and UnitName("player") or "Player"
	if type(name) ~= "string" or name == "" then name = "Player" end
	return name
end

function ns.Current()
	local realm, name = ns.Realm(), ns.Name()
	local chars = ns.db.chars
	chars[realm] = chars[realm] or {}
	local c = chars[realm][name]
	if not c then
		c = { name = name, realm = realm }
		chars[realm][name] = c
	end
	return c
end

function ns.All()
	local out = {}
	for realm, list in pairs(ns.db.chars) do
		if type(list) == "table" then
			for name, c in pairs(list) do
				if type(c) == "table" then
					c.name = c.name or name
					c.realm = c.realm or realm
					out[#out + 1] = c
				end
			end
		end
	end
	return out
end

function ns.IsCurrent(c)
	return c.name == ns.Name() and c.realm == ns.Realm()
end

function ns.Delete(c)
	local list = ns.db.chars[c.realm]
	if not list then return end
	list[c.name] = nil
	if next(list) == nil then ns.db.chars[c.realm] = nil end
	ns:Fire("CHARS_CHANGED")
end

function ns.Ago(t)
	if not t or t <= 0 then return "never" end
	local d = ns.Now() - t
	if d < 90 then return "now" end
	if d < 3600 then return math.floor(d / 60) .. " min ago" end
	if d < 86400 then return math.floor(d / 3600) .. " h ago" end
	return math.floor(d / 86400) .. " d ago"
end

function ns.Duration(s)
	s = math.floor(s or 0)
	if s <= 0 then return "0 min" end
	local d = math.floor(s / 86400)
	local h = math.floor(s / 3600) % 24
	local m = math.floor(s / 60) % 60
	if d > 0 then return d .. " d " .. h .. " h" end
	if h > 0 then return h .. " h " .. m .. " min" end
	return m .. " min"
end

function ns.Options()
	local UI = ns.UI
	local db = ns.db
	return {
		{ text = "Options", title = true },
		UI.Check(db, "tooltip", "Show which characters own an item in tooltips"),
		UI.Check(db, "played", "Record played time at login"),
	}
end

SLASH_AALTS1 = "/aalts"
SLASH_AALTS2 = "/alts"
SlashCmdList["AALTS"] = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd = msg:lower()
	if cmd == "" then
		ns.Window.Toggle()
	elseif cmd == "reset" then
		ns.db.window.pos = nil
		ns.db.window.scale = 1
		ns:Fire("LAYOUT_RESET")
	elseif cmd == "scan" then
		ns.ScanAll()
		ns.Print("Saved " .. ns.Name())
	else
		ns.Window.Show()
		ns.Window.SetSearch(msg)
	end
end

BINDING_HEADER_AALTS = "AAlts"
BINDING_NAME_AALTS_TOGGLE = "Toggle character overview"
function AAlts_ToggleBinding()
	ns.Window.Toggle()
end
