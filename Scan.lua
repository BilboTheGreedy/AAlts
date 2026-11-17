local _, ns = ...

local function num(v)
	if type(v) ~= "number" or ns.IsSecret(v) then return nil end
	return v
end

local function str(v)
	if type(v) ~= "string" or ns.IsSecret(v) or v == "" then return nil end
	return v
end

local function pass(ok, ...)
	if ok then return ... end
end

local function call(fn, ...)
	if not fn then return nil end
	return pass(pcall(fn, ...))
end

local function basics(c)
	c.class = ns.playerClass
	c.faction = ns.playerFaction
	local race = call(UnitRace, "player")
	c.race = str(race) or c.race
	c.level = num(call(UnitLevel, "player")) or c.level or 1
	c.xp = num(call(UnitXP, "player")) or 0
	c.xpMax = num(call(UnitXPMax, "player")) or 0
	c.rested = num(call(GetXPExhaustion)) or 0
	local max = num(call(GetMaxPlayerLevel)) or 60
	c.capped = c.level >= max
	local money = num(call(GetMoney)) or c.money or 0
	local day = date and date("%Y-%m-%d")
	if day and c.day ~= day then c.day, c.dayStart = day, c.money or money end
	c.money = money
	local zone = call(GetRealZoneText)
	if not str(zone) then zone = call(GetZoneText) end
	c.zone = str(zone) or c.zone
	local guild, guildRank = call(GetGuildInfo, "player")
	c.guild = str(guild)
	c.guildRank = c.guild and str(guildRank) or nil
	c.resting = call(IsResting) and true or false
	c.seen = ns.Now()
end

local function trim(v)
	if type(v) ~= "string" then return nil end
	return (v:gsub(":%s*$", ""))
end

local function skillLines()
	local out = {}
	if not GetNumSkillLines or not GetSkillLineInfo then return out end
	local lines = {}
	local main, second = trim(rawget(_G, "TRADE_SKILLS")), trim(rawget(_G, "SECONDARY_SKILLS"))
	local header, named, section = 0, false, false
	for i = 1, num(call(GetNumSkillLines)) or 0 do
		local name, isHeader, _, rank, _, _, max, abandon = call(GetSkillLineInfo, i)
		if isHeader then
			header = header + 1
			local n = trim(str(name))
			section = n ~= nil and (n == main or n == second)
			if section then named = true end
		elseif str(name) and num(rank) and num(max) and max > 1 then
			lines[#lines + 1] = { name = name, rank = rank, max = max, main = abandon and true or false, section = section, header = header }
		end
	end
	for _, l in ipairs(lines) do
		local keep = l.main or l.section
		if not named and (l.header == 2 or l.header == 3) then keep = true end
		if keep then out[#out + 1] = { name = l.name, rank = l.rank, max = l.max, main = l.main } end
	end
	return out
end

local function professions(c)
	local out = skillLines()
	if #out == 0 and GetProfessions and GetProfessionInfo then
		local list = { call(GetProfessions) }
		for i = 1, 6 do
			local index = list[i]
			if index then
				local name, _, rank, max = call(GetProfessionInfo, index)
				if str(name) and num(rank) then
					out[#out + 1] = { name = name, rank = rank, max = num(max) or rank, main = i <= 2 }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.main ~= b.main then return a.main end
		return a.name < b.name
	end)
	c.profs = out
end

local COOLDOWNS = {
	{ name = "Transmute", spells = { 17187, 11479, 11480, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566, 25146 } },
	{ name = "Mooncloth", spells = { 18560 } },
	{ name = "Salt Shaker", spells = { 19566 } },
}

local function spellCooldown(id)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = call(C_Spell.GetSpellCooldown, id)
		if type(info) == "table" then return num(info.startTime), num(info.duration) end
		return nil
	end
	if GetSpellCooldown then
		local start, duration = call(GetSpellCooldown, id)
		return num(start), num(duration)
	end
end

local function known(id)
	if IsPlayerSpell and call(IsPlayerSpell, id) then return true end
	if IsSpellKnown and call(IsSpellKnown, id) then return true end
	return false
end

local function cooldowns(c)
	local old = {}
	for _, cd in ipairs(c.cooldowns or {}) do old[cd.name] = cd end
	local out = {}
	local now = GetTime and GetTime() or 0
	for _, cd in ipairs(COOLDOWNS) do
		local ready, have = nil, false
		for _, id in ipairs(cd.spells) do
			local start, duration = spellCooldown(id)
			if start and duration and start > 0 and duration > 60 then
				ready = ns.Now() + math.max(0, start + duration - now)
				break
			end
			if not have and known(id) then have = true end
		end
		local prev = old[cd.name]
		if ready then
			if prev and math.abs((prev.ready or 0) - ready) < 10 then
				out[#out + 1] = prev
			else
				out[#out + 1] = { name = cd.name, ready = ready }
			end
		elseif prev then
			out[#out + 1] = prev
		elseif have then
			out[#out + 1] = { name = cd.name, ready = 0 }
		end
	end
	c.cooldowns = out
end

local SLOTS = {
	{ 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" },
	{ 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { 11, "Finger" }, { 12, "Finger" },
	{ 13, "Trinket" }, { 14, "Trinket" }, { 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged" },
}
ns.SLOTS = SLOTS

local function itemLevel(link)
	if C_Item and C_Item.GetDetailedItemLevelInfo then
		local l = num(call(C_Item.GetDetailedItemLevelInfo, link))
		if l then return l end
	end
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if info then
		local _, _, _, l = call(info, link)
		return num(l)
	end
end

local function gear(c)
	if not GetInventoryItemLink then return end
	local out = {}
	local sum, count = 0, 0
	for _, s in ipairs(SLOTS) do
		local link = str(call(GetInventoryItemLink, "player", s[1]))
		if link then
			out[s[1]] = link
			local l = itemLevel(link)
			if l then
				sum = sum + l
				count = count + 1
			end
		end
	end
	c.gear = out
	c.ilvl = count > 0 and math.floor(sum / count * 10 + 0.5) / 10 or 0
end

local function slots(bag)
	local total, free
	if C_Container and C_Container.GetContainerNumSlots then
		total = num(call(C_Container.GetContainerNumSlots, bag))
		free = num(call(C_Container.GetContainerNumFreeSlots, bag))
	elseif GetContainerNumSlots then
		total = num(call(GetContainerNumSlots, bag))
		free = num(call(GetContainerNumFreeSlots, bag))
	end
	return total or 0, free or 0
end

local function bags(c)
	local total, free = 0, 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local t, f = slots(bag)
		total, free = total + t, free + f
	end
	c.bagTotal, c.bagFree = total, free
end

local function bank(c)
	local total, free = slots(BANK_CONTAINER or -1)
	local first = (NUM_BAG_SLOTS or 4) + 1
	for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do
		local t, f = slots(bag)
		total, free = total + t, free + f
	end
	if total > 0 then
		c.bankTotal, c.bankFree = total, free
		c.bankSeen = ns.Now()
	end
end

local function reputations(c)
	local out = {}
	local collapsed = false
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		for i = 1, num(call(C_Reputation.GetNumFactions)) or 0 do
			local d = call(C_Reputation.GetFactionDataByIndex, i)
			if type(d) == "table" and d.isHeader and d.isCollapsed then collapsed = true end
			if type(d) == "table" and str(d.name) and (not d.isHeader or d.isHeaderWithRep) then
				local standing = num(d.reaction) or 4
				local value = num(d.currentStanding) or 0
				local lo = num(d.currentReactionThreshold) or 0
				local hi = num(d.nextReactionThreshold) or lo
				if standing ~= 4 or value ~= lo then
					out[#out + 1] = { name = d.name, id = d.factionID, standing = standing, value = value - lo, max = hi - lo }
				end
			end
		end
	elseif GetNumFactions and GetFactionInfo then
		for i = 1, num(call(GetNumFactions)) or 0 do
			local name, _, standing, lo, hi, value, _, _, isHeader, isCollapsed, hasRep, _, _, id = call(GetFactionInfo, i)
			if isHeader and isCollapsed then collapsed = true end
			if str(name) and (not isHeader or hasRep) and num(standing) and num(value) then
				lo, hi = num(lo) or 0, num(hi) or 0
				if standing ~= 4 or value ~= lo then
					out[#out + 1] = { name = name, id = id, standing = standing, value = value - lo, max = hi - lo }
				end
			end
		end
	else
		return
	end
	if collapsed and c.reps then
		local have = {}
		for _, r in ipairs(out) do have[r.name] = true end
		for _, r in ipairs(c.reps) do
			if not have[r.name] then out[#out + 1] = r end
		end
	end
	table.sort(out, function(a, b)
		if a.standing ~= b.standing then return a.standing > b.standing end
		if a.value ~= b.value then return a.value > b.value end
		return a.name < b.name
	end)
	c.reps = out
end

local function lockouts(c)
	if not GetNumSavedInstances or not GetSavedInstanceInfo then return end
	local out = {}
	for i = 1, num(call(GetNumSavedInstances)) or 0 do
		local name, id, reset, _, locked, _, _, isRaid, _, diffName = call(GetSavedInstanceInfo, i)
		if str(name) and num(reset) and reset > 0 and locked ~= false then
			out[#out + 1] = { name = name, id = id, reset = ns.Now() + reset, raid = isRaid and true or false, diff = str(diffName) }
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	c.lockouts = out
end

local function rank(c)
	if not UnitPVPRank or not GetPVPRankInfo then return end
	local r = num(call(UnitPVPRank, "player"))
	if not r or r == 0 then
		c.rank = nil
		return
	end
	local name, number = call(GetPVPRankInfo, r)
	if str(name) then c.rank = { name = name, number = num(number) or 0 } end
end

local function mail(c, atBox)
	if atBox and GetInboxNumItems then
		local shown, total = call(GetInboxNumItems)
		c.mail = num(total) or num(shown) or 0
		c.mailSeen = ns.Now()
		local soonest
		if GetInboxHeaderInfo then
			for i = 1, num(shown) or 0 do
				local _, _, _, _, _, _, days = call(GetInboxHeaderInfo, i)
				days = num(days)
				if days and (not soonest or days < soonest) then soonest = days end
			end
		end
		c.mailExpire = soonest and (ns.Now() + math.floor(soonest * 86400)) or nil
	elseif HasNewMail then
		c.newMail = call(HasNewMail) and true or false
	end
end

function ns.ScanAll()
	local c = ns.Current()
	basics(c)
	professions(c)
	cooldowns(c)
	gear(c)
	bags(c)
	reputations(c)
	lockouts(c)
	rank(c)
	mail(c)
	ns:Fire("CHARS_CHANGED")
	return c
end

local function later(key, fn)
	ns.Debounce(key, 1, function()
		if not ns.db then return end
		fn(ns.Current())
		ns:Fire("CHARS_CHANGED")
	end)
end

local silenced = {}
local waiting = false

local function restoreChat()
	for _, f in ipairs(silenced) do pcall(f.RegisterEvent, f, "TIME_PLAYED_MSG") end
	silenced = {}
	waiting = false
end

local function askPlayed()
	if not ns.db.played or not RequestTimePlayed or waiting then return end
	waiting = true
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local f = _G["ChatFrame" .. i]
		if f and f.IsEventRegistered and f.UnregisterEvent then
			local ok, reg = pcall(f.IsEventRegistered, f, "TIME_PLAYED_MSG")
			if ok and reg then
				pcall(f.UnregisterEvent, f, "TIME_PLAYED_MSG")
				silenced[#silenced + 1] = f
			end
		end
	end
	pcall(RequestTimePlayed)
	ns.After(8, function()
		if waiting then restoreChat() end
	end)
end

ns:On("TIME_PLAYED_MSG", function(total, level)
	if ns.db then
		local c = ns.Current()
		c.played = num(total) or c.played
		c.playedLevel = num(level) or c.playedLevel
		c.playedAt = ns.Now()
	end
	if waiting then ns.After(0, restoreChat) end
	ns:Fire("CHARS_CHANGED")
end)

function ns.Alerts()
	local out = {}
	local now = ns.Now()
	for _, c in ipairs(ns.All()) do
		if not ns.IsCurrent(c) then
			for _, cd in ipairs(c.cooldowns or {}) do
				if (cd.ready or 0) > 0 and cd.ready <= now and not cd.told then
					cd.told = true
					out[#out + 1] = cd.name .. " ready on " .. c.name
				end
			end
			if c.mailExpire and (c.mail or 0) > 0 and c.mailExpire - now < 3 * 86400 and (c.mailTold or 0) < now - 86400 then
				c.mailTold = now
				if c.mailExpire > now then
					out[#out + 1] = "Mail on " .. c.name .. " expires in " .. ns.Duration(c.mailExpire - now)
				else
					out[#out + 1] = "Mail on " .. c.name .. " may have expired"
				end
			end
		end
	end
	return out
end

ns:Listen("LOGIN", function()
	ns.ScanAll()
	if RequestRaidInfo then pcall(RequestRaidInfo) end
	ns.After(4, askPlayed)
	ns.After(6, function()
		if not ns.db or not ns.db.alerts then return end
		for _, line in ipairs(ns.Alerts()) do ns.Print(line) end
	end)
end)

ns:On("PLAYER_MONEY", function() later("basics", basics) end)
ns:On("PLAYER_XP_UPDATE", function() later("basics", basics) end)
ns:On("PLAYER_LEVEL_UP", function() later("basics", basics) end)
ns:On("ZONE_CHANGED_NEW_AREA", function() later("basics", basics) end)
ns:On("PLAYER_UPDATE_RESTING", function() later("basics", basics) end)
ns:On("PLAYER_GUILD_UPDATE", function() later("basics", basics) end)
ns:On("SKILL_LINES_CHANGED", function() later("profs", professions) end)
ns:On("CHAT_MSG_SKILL", function() later("profs", professions) end)
ns:On("TRADE_SKILL_UPDATE", function() later("cooldowns", cooldowns) end)
ns:On("SPELL_UPDATE_COOLDOWN", function()
	ns.Debounce("cooldowns", 5, function()
		if ns.db then cooldowns(ns.Current()) end
	end)
end)
ns:On("PLAYER_EQUIPMENT_CHANGED", function() later("gear", gear) end)
ns:On("BAG_UPDATE_DELAYED", function() later("bags", bags) end)
ns:On("BANKFRAME_OPENED", function()
	ns.atBank = true
	later("bank", bank)
end)
ns:On("BANKFRAME_CLOSED", function() ns.atBank = false end)
ns:On("PLAYERBANKSLOTS_CHANGED", function()
	if ns.atBank then later("bank", bank) end
end)
ns:On("UPDATE_FACTION", function() later("reps", reputations) end)
ns:On("UPDATE_INSTANCE_INFO", function() later("lockouts", lockouts) end)
ns:On("PLAYER_PVP_RANK_CHANGED", function() later("rank", rank) end)
ns:On("MAIL_INBOX_UPDATE", function()
	later("mail", function(c) mail(c, true) end)
end)
ns:On("UPDATE_PENDING_MAIL", function()
	later("newmail", function(c) mail(c) end)
end)
ns:On("PLAYER_LOGOUT", function()
	if ns.db then basics(ns.Current()) end
end)
