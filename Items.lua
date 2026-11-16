local _, ns = ...

local index, built = nil, 0

local function source()
	local db = rawget(_G, "ABagDB")
	if type(db) ~= "table" or type(db.chars) ~= "table" then return nil end
	return db.chars
end

function ns.HasBags()
	return source() ~= nil
end

local function currentKey()
	return ns.Name() .. " - " .. ns.Realm()
end

local function addList(key, who, list, field)
	if type(list) ~= "table" then return end
	for _, s in ipairs(list) do
		if type(s) == "string" then
			local id, count = s:match("^(%d+):(%d+)$")
			id, count = tonumber(id), tonumber(count)
			if id and count then
				local owners = index[id]
				if not owners then
					owners = {}
					index[id] = owners
				end
				local o = owners[key]
				if not o then
					o = { key = key, who = who, bags = 0, bank = 0 }
					owners[key] = o
				end
				o[field] = o[field] + count
			end
		end
	end
end

function ns.Stored()
	local now = ns.Now()
	if index and now - built < 10 then return index end
	index = {}
	built = now
	local chars = source()
	if not chars then return index end
	for key, c in pairs(chars) do
		if type(c) == "table" then
			local who = type(c.name) == "string" and c.name or tostring(key)
			addList(key, who, c.bags, "bags")
			addList(key, who, c.bank, "bank")
		end
	end
	return index
end

function ns.Owners(id, skipCurrent)
	local owners = ns.Stored()[id]
	if not owners then return nil end
	local out = {}
	local me = currentKey()
	for key, o in pairs(owners) do
		if not (skipCurrent and key == me) then out[#out + 1] = o end
	end
	if #out == 0 then return nil end
	table.sort(out, function(a, b) return a.who < b.who end)
	return out
end

local function itemName(id)
	local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not info then return nil end
	local ok, name, link, quality = pcall(info, id)
	if ok and type(name) == "string" then return name, link, quality end
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	return nil
end
ns.ItemName = itemName

function ns.OwnerText(o)
	local parts = {}
	if o.bags > 0 then parts[#parts + 1] = o.bags end
	if o.bank > 0 then parts[#parts + 1] = o.bank .. " in bank" end
	return o.who .. " (" .. table.concat(parts, ", ") .. ")"
end

function ns.FindItems(query)
	local words = {}
	for w in query:lower():gmatch("%S+") do words[#words + 1] = w end
	local out = {}
	if #words == 0 then return out end
	for id in pairs(ns.Stored()) do
		local name, link, quality = itemName(id)
		local text = (name or ("item " .. id)):lower()
		local hit = true
		for i = 1, #words do
			if not text:find(words[i], 1, true) and tostring(id) ~= words[i] then hit = false break end
		end
		if hit then
			local total = 0
			local owners = ns.Owners(id)
			for _, o in ipairs(owners) do total = total + o.bags + o.bank end
			out[#out + 1] = { kind = "item", id = id, name = name or ("Item " .. id), link = link, quality = quality or 1, owners = owners, total = total }
		end
	end
	table.sort(out, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	return out
end

local function addLines(tooltip, id)
	if not ns.db or not ns.db.tooltip then return end
	if type(id) ~= "number" or ns.IsSecret(id) then return end
	local owners = ns.Owners(id, true)
	if not owners then return end
	local parts = {}
	for i, o in ipairs(owners) do
		if i > 4 then
			parts[#parts + 1] = "+" .. (#owners - 4) .. " more"
			break
		end
		parts[#parts + 1] = ns.OwnerText(o)
	end
	tooltip:AddLine("Also on: " .. table.concat(parts, ", "), 0.55, 0.8, 1, true)
	tooltip:Show()
end

local function fromData(tooltip, data)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	addLines(tooltip, data and data.id)
end

local function fromLegacy(tooltip)
	if not tooltip.GetItem then return end
	local _, link = tooltip:GetItem()
	if type(link) ~= "string" then return end
	addLines(tooltip, tonumber(link:match("item:(%d+)")))
end

ns:Listen("LOGIN", function()
	local hooked = false
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip, data)
			pcall(fromData, tooltip, data)
		end)
	end
	if not hooked and GameTooltip and GameTooltip.HookScript then
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tooltip)
			pcall(fromLegacy, tooltip)
		end)
	end
end)
