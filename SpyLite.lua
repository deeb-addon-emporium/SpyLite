-- SpyLite: enemy players near you, from what the client still lets an addon see.
-- Sources: nameplates appearing, your target, your mouseover, your group's targets.
-- NOT the combat log: this client forbids addons from reading it, so nothing here can see
-- an enemy before they are on your screen.
-- Values that come back secret (name, level...) are shown as "?" and never compared.
local PREFIX = "|cffff6060SpyLite|r: "
local function msg(t) print(PREFIX .. t) end

local function plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local db
local seen = {}            -- name -> record (this session)
local order = {}           -- names, most recent first
local MAX_ROWS = 10
local RESEEN = 60          -- seconds before the same player alerts again

local CLASS_COLOR = {}
local function classColor(class)
	if not class then return 1, 1, 1 end
	local c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

local win, rows

local function refresh()
	if not win or not win:IsShown() then return end
	for i, row in ipairs(rows) do
		local name = order[i]
		local r = name and seen[name]
		if r then
			local ago = math.floor(GetTime() - r.at)
			row.name:SetText(r.name or "?")
			row.name:SetTextColor(classColor(r.class))
			row.info:SetText(string.format("%s %s  %s", r.level and tostring(r.level) or "??", r.className or "?", ago < 60 and (ago .. "s") or (math.floor(ago / 60) .. "m")))
			row.entry = r
			row:Show()
		else
			row.entry = nil
			row:Hide()
		end
	end
	win.count:SetText(#order > 0 and (#order .. " seen") or "nothing seen")
end

local function alert(r, fresh)
	if fresh and db.sound ~= false then
		pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
	end
	if fresh and db.chat ~= false then
		msg(string.format("|cffff6060%s|r  %s %s%s", r.name or "?", r.level and tostring(r.level) or "??", r.className or "?", r.guild and ("  <" .. r.guild .. ">") or ""))
	end
	if fresh and db.warn ~= false and RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, string.format("%s  %s %s", r.name or "Enemy", r.level and tostring(r.level) or "", r.className or ""), ChatTypeInfo["RAID_WARNING"])
	end
end

local function sight(unit, source)
	if not db or db.enabled == false then return end
	if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
	if UnitIsUnit(unit, "player") or not UnitCanAttack("player", unit) then return end
	if UnitIsDeadOrGhost(unit) then return end
	local name = plain(UnitName(unit))
	local guid = plain(UnitGUID(unit))
	local key = name or guid or ("unknown-" .. tostring(unit))
	local className, class = UnitClass(unit)
	local level = plain(UnitLevel(unit))
	if level == -1 then level = "??" end
	local guild = plain(GetGuildInfo(unit))
	local now = GetTime()
	local r = seen[key]
	local fresh = not r or (now - r.at) > RESEEN
	if not r then r = { first = now }; seen[key] = r end
	r.name = name; r.guid = guid; r.className = plain(className); r.class = plain(class)
	r.level = level; r.guild = guild; r.at = now; r.source = source
	r.zone = GetRealZoneText(); r.sub = GetSubZoneText()
	-- most recent first
	for i, n in ipairs(order) do if n == key then table.remove(order, i); break end end
	table.insert(order, 1, key)
	while #order > 50 do table.remove(order) end
	-- account-wide history
	db.history = db.history or {}
	local h = db.history[key] or { count = 0 }
	h.count = h.count + 1; h.last = time(); h.name = name; h.className = r.className; h.level = level; h.guild = guild; h.zone = r.zone
	db.history[key] = h
	alert(r, fresh)
	refresh()
end

-- ---- window ----
local function build()
	win = CreateFrame("Frame", "SpyLiteFrame", UIParent, "BackdropTemplate")
	win:SetSize(200, 20 + MAX_ROWS * 16 + 8)
	win:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -200)
	win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); local p, _, rp, x, y = self:GetPoint(); db.pos = { p, rp, x, y } end)
	win:SetClampedToScreen(true)
	if win.SetBackdrop then
		win:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		win:SetBackdropColor(0, 0, 0, 0.6)
	end
	local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 8, -5); title:SetText("|cffff6060SpyLite|r")
	win.count = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.count:SetPoint("TOPRIGHT", -24, -7)
	local clear = CreateFrame("Button", nil, win)
	clear:SetSize(16, 16); clear:SetPoint("TOPRIGHT", -5, -5)
	clear:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
	clear:SetScript("OnClick", function() seen = {}; order = {}; refresh() end)
	rows = {}
	for i = 1, MAX_ROWS do
		-- secure so a click can target by name
		local row = CreateFrame("Button", "SpyLiteRow" .. i, win, "SecureActionButtonTemplate")
		row:SetSize(184, 16); row:SetPoint("TOPLEFT", 8, -20 - (i - 1) * 16)
		row:RegisterForClicks("AnyUp", "AnyDown")
		row:SetAttribute("type", "macro")
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.name:SetPoint("LEFT", 2, 0); row.name:SetWidth(96); row.name:SetJustifyH("LEFT")
		row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); row.info:SetPoint("RIGHT", -2, 0); row.info:SetWidth(84); row.info:SetJustifyH("RIGHT")
		row:SetScript("PreClick", function(self)
			if InCombatLockdown() then return end
			local r = self.entry
			self:SetAttribute("macrotext", (r and r.name) and ("/targetexact " .. r.name) or "")
		end)
		rows[i] = row
	end
	if db.pos then win:ClearAllPoints(); win:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4]) end
	if db.shown == false then win:Hide() end
	refresh()
end

-- ---- events ----
local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_TARGET", "PLAYER_ENTERING_WORLD" }) do
	pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_LOGIN" then
		if type(SpyLiteDB) ~= "table" then SpyLiteDB = {} end
		db = SpyLiteDB
		build()
		C_Timer.After(3, function() msg("watching plates, target and mouseover - /spy") end)
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		pcall(sight, unit, "plate")
	elseif event == "PLAYER_TARGET_CHANGED" then
		pcall(sight, "target", "target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		pcall(sight, "mouseover", "mouseover")
	elseif event == "UNIT_TARGET" then
		if unit and (string.find(unit, "^party") or string.find(unit, "^raid")) then pcall(sight, unit .. "target", "group") end
	elseif event == "PLAYER_ENTERING_WORLD" then
		seen = {}; order = {}; refresh()
	end
end)
C_Timer.NewTicker(5, refresh)

-- ---- slash ----
SLASH_SPYLITE1 = "/spy"
SlashCmdList.SPYLITE = function(input)
	local cmd = string.lower(strtrim(input or ""))
	if cmd == "sound" then db.sound = not (db.sound ~= false); msg("sound " .. (db.sound and "on" or "off"))
	elseif cmd == "warn" then db.warn = not (db.warn ~= false); msg("screen warning " .. (db.warn and "on" or "off"))
	elseif cmd == "chat" then db.chat = not (db.chat ~= false); msg("chat line " .. (db.chat and "on" or "off"))
	elseif cmd == "off" then db.enabled = false; msg("off")
	elseif cmd == "on" then db.enabled = true; msg("on")
	elseif cmd == "history" then
		local list = {}
		for _, h in pairs(db.history or {}) do list[#list + 1] = h end
		table.sort(list, function(a, b) return (a.last or 0) > (b.last or 0) end)
		for i = 1, math.min(15, #list) do local h = list[i]; msg(string.format("%s  %s %s  x%d  %s  %s", h.name or "?", tostring(h.level or "?"), h.className or "?", h.count, h.zone or "", date("%d %b %H:%M", h.last))) end
		if #list == 0 then msg("no history yet") end
	elseif cmd == "probe" then
		local u = UnitExists("target") and "target" or (UnitExists("mouseover") and "mouseover" or nil)
		if not u then msg("probe: target or mouse over an enemy player first"); return end
		local n = UnitName(u); local l = UnitLevel(u); local _, c = UnitClass(u)
		msg(string.format("probe: player=%s hostile=%s name secret=%s level secret=%s class=%s", tostring(UnitIsPlayer(u)), tostring(UnitCanAttack("player", u)), tostring(issecretvalue and issecretvalue(n)), tostring(issecretvalue and issecretvalue(l)), tostring(c)))
	else
		if win:IsShown() then win:Hide(); db.shown = false else win:Show(); db.shown = true; refresh() end
	end
end
