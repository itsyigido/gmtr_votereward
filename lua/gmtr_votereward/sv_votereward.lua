-- gmtr_votereward sunucu: oy doğrulama (gmod.tr API), ödül çekilişi, teslim ve bekleyen ödüller.
util.AddNetworkString("gmtr_vr_msg")
util.AddNetworkString("gmtr_vr_open")

local VR = GMTR_VR
local CFG = setmetatable({}, {__index = function(_, key) return GMTR_VR.Config[key] end})
local API = "https://gmod.tr/api/v1"
local DATA_DIR = "gmtr_votereward"
local PENDING_FILE = DATA_DIR .. "/pending.json"
local LOG_FILE = DATA_DIR .. "/log.txt"
local COOLDOWN = 5

file.CreateDir(DATA_DIR)

VR.Busy = VR.Busy or {}
VR.NextUse = VR.NextUse or {}
VR.Reminded = VR.Reminded or {}
VR.NextOpen = VR.NextOpen or {}

local MESSAGES = {
	NotConfigured = "Oy ödülü sistemi henüz yapılandırılmadı.",
	Wait = "Biraz bekleyip tekrar dene.",
	NoCharacter = "Önce bir karakter seçmelisin.",
	Checking = "Oyun kontrol ediliyor...",
	Success = "Oy verdiğin için teşekkürler! Ödülün: {reward}",
	NotVoted = "Son 24 saatte sunucumuza oy vermemişsin. /oyver yazarak oy verebilirsin.",
	AlreadyClaimed = "Bu günün oy ödülünü zaten aldın. Oy hakkın her gün 12:00'de yenilenir.",
	RateLimited = "Şu an çok fazla istek var, birazdan tekrar dene.",
	ApiError = "gmod.tr'ye şu an ulaşılamıyor, daha sonra tekrar dene.",
	PoolEmpty = "Ödül havuzu şu an kullanılamıyor, lütfen bir yetkiliye haber ver.",
	GiveFailed = "Ödülün verilemedi, lütfen bir yetkiliye haber ver.",
	PendingSaved = "Ödülün kaydedildi; bir sonraki girişinde teslim edilecek.",
	PendingDelivered = "Bekleyen oy ödülün teslim edildi: {reward}",
	VoteOpen = "Oy sayfası açıldı; açılmazsa link panona kopyalandı, tarayıcına yapıştır.",
	RemindNotVoted = "Bugün sunucumuza oy vermedin! /oyver ile oy ver, sonra /reward ile ödülünü al.",
	RemindUnclaimed = "Oyun için bir ödülün bekliyor: /reward yazarak al.",
}

local function Format(key, vars)
	vars = vars or {}

	return (string.gsub(MESSAGES[key] or key, "{(%w+)}", function(name)
		return vars[name] and tostring(vars[name]) or nil
	end))
end

local function Msg(client, key, vars)
	if (!IsValid(client)) then return end

	net.Start("gmtr_vr_msg")
		net.WriteString(Format(key, vars))
	net.Send(client)
end

local function Log(text)
	file.Append(LOG_FILE, os.date("[%d.%m.%Y %H:%M:%S] ") .. text .. "\n")
end

local function Who(client, sid)
	return (IsValid(client) and client:Name() or "?") .. " (" .. sid .. ")"
end

local function KeyOK()
	return isstring(VR.ApiKey) and string.StartWith(VR.ApiKey, "gmtr_")
end

local function Request(method, path, callback)
	local ok = HTTP({
		method = method,
		url = API .. path,
		headers = {Authorization = "Bearer " .. VR.ApiKey, Accept = "application/json"},
		body = method == "POST" and "{}" or nil,
		type = method == "POST" and "application/json" or nil,
		timeout = 10,
		success = function(code, body)
			callback(code, util.JSONToTable(body or "") or {})
		end,
		failed = function(reason)
			callback(0, {detail = tostring(reason)})
		end
	})

	-- İstek hiç başlamazsa callback gelmez; kuyruk ve kilitler takılı kalmasın
	if (ok == false) then callback(0, {detail = "HTTP başlatılamadı"}) end
end

-- Çerçeve uyumu (Helix / DarkRP / düz)

local function GetCharacter(client)
	return ix and client.GetCharacter and client:GetCharacter() or nil
end

local function IsReady(client)
	return !ix or GetCharacter(client) != nil
end

local function FormatMoney(amount)
	if (ix and ix.currency) then return ix.currency.Get(amount) end
	if (DarkRP and DarkRP.formatMoney) then return DarkRP.formatMoney(amount) end

	return tostring(amount)
end

-- Ödül tipleri

local function Amount(reward)
	return math.max(math.floor(tonumber(reward.amount) or 1), 1)
end

local Types = {}

Types.money = {
	Valid = function(reward)
		return (tonumber(reward.amount) or 0) > 0 and (ix != nil or DarkRP != nil)
	end,
	Name = function(reward)
		return FormatMoney(Amount(reward))
	end,
	Grant = function(client, character, reward)
		if (ix) then
			if (!character) then return false end

			character:GiveMoney(Amount(reward))

			return true
		end

		if (!client.addMoney) then return false end

		client:addMoney(Amount(reward))

		return true
	end
}

Types.item = {
	Valid = function(reward)
		return ix != nil and ix.item.list[reward.item or ""] != nil
	end,
	Name = function(reward)
		local amount = Amount(reward)

		return ix.item.list[reward.item].name .. (amount > 1 and (" x" .. amount) or "")
	end,
	Grant = function(client, character, reward)
		local inventory = character and character:GetInventory()

		if (!inventory) then return false end

		for _ = 1, Amount(reward) do
			if (!inventory:Add(reward.item, 1, reward.data)) then
				ix.item.Spawn(reward.item, client, nil, nil, reward.data)
			end
		end

		return true
	end
}

-- Helix'te silahlar item'dır; ham silah vermek envanteri atlar.
Types.weapon = {
	Valid = function(reward)
		return !ix and isstring(reward.class) and reward.class != ""
	end,
	Name = function(reward)
		local stored = weapons.GetStored(reward.class)

		return stored and stored.PrintName or reward.class
	end,
	Grant = function(client, character, reward)
		client:Give(reward.class)

		return client:HasWeapon(reward.class)
	end
}

local function FindShipment(name)
	name = string.lower(name or "")

	for index, shipment in pairs(CustomShipments or {}) do
		if (string.lower(shipment.name or "") == name) then
			return shipment, index
		end
	end
end

Types.shipment = {
	Valid = function(reward)
		return DarkRP != nil and FindShipment(reward.shipment) != nil
	end,
	Name = function(reward)
		local shipment = FindShipment(reward.shipment)

		return shipment.name .. " kolisi (x" .. (tonumber(reward.count) or shipment.amount) .. ")"
	end,
	Grant = function(client, character, reward)
		local shipment, index = FindShipment(reward.shipment)

		if (!shipment) then return false end

		local trace = util.TraceLine({
			start = client:EyePos(),
			endpos = client:EyePos() + client:GetAimVector() * 85,
			filter = client
		})

		local crate = ents.Create(shipment.shipmentClass or "spawned_shipment")

		if (!IsValid(crate)) then return false end

		crate.SID = client.SID
		crate:Setowning_ent(client)
		crate:SetContents(index, tonumber(reward.count) or shipment.amount)
		crate:SetPos(trace.HitPos + trace.HitNormal * 16)
		crate.nodupe = true
		crate.ammoadd = shipment.spareammo
		crate.clip1 = shipment.clip1
		crate.clip2 = shipment.clip2
		crate:Spawn()
		crate:SetPlayer(client)

		local phys = crate:GetPhysicsObject()

		if (IsValid(phys)) then
			phys:Wake()
			if (shipment.weight) then phys:SetMass(shipment.weight) end
		end

		return true
	end
}

Types.command = {
	Valid = function(reward)
		return isstring(reward.command) and reward.command != ""
	end,
	Name = function(reward)
		return "Özel ödül"
	end,
	Grant = function(client, character, reward)
		-- TUZAK: isim oyuncunun elinde; ; ve tırnak temizlenmezse konsola komut enjekte edilir.
		local vars = {
			steamid = client:SteamID(),
			steamid64 = client:SteamID64(),
			userid = client:UserID(),
			name = string.gsub(client:Name(), "[%c\"';\\]", "")
		}

		local command = string.gsub(reward.command, "{(%w+)}", function(key)
			return vars[key] and tostring(vars[key]) or nil
		end)

		game.ConsoleCommand(command .. "\n")

		return true
	end
}

local function GetType(reward)
	if (isfunction(reward.Grant)) then return "custom" end

	return Types[reward.type or ""]
end

local function IsValidReward(reward)
	local rewardType = GetType(reward)

	if (rewardType == "custom") then return true end
	if (istable(rewardType)) then return rewardType.Valid(reward) == true end

	return false
end

local function RewardName(reward)
	if (reward.name) then return reward.name end

	local rewardType = GetType(reward)

	if (istable(rewardType)) then return rewardType.Name(reward) end

	return "Ödül"
end

local function Grant(client, reward)
	local character = GetCharacter(client)
	local rewardType = GetType(reward)
	local ok, result

	if (rewardType == "custom") then
		ok, result = pcall(reward.Grant, client, character)
		if (ok) then result = result != false end
	elseif (istable(rewardType)) then
		ok, result = pcall(rewardType.Grant, client, character, reward)
	else
		return false
	end

	if (!ok) then
		ErrorNoHalt("[gmtr_votereward] Ödül hatası: " .. tostring(result) .. "\n")
		return false
	end

	return result == true
end

local function Roll(exclude)
	local pool, total = {}, 0

	for _, reward in ipairs(CFG.Rewards or {}) do
		local weight = tonumber(reward.weight) or 0

		if (weight > 0 and !(exclude and exclude[reward]) and IsValidReward(reward)) then
			pool[#pool + 1] = reward
			total = total + weight
		end
	end

	if (total <= 0) then return nil end

	local roll = math.random() * total

	for _, reward in ipairs(pool) do
		roll = roll - reward.weight

		if (roll <= 0) then return reward end
	end

	return pool[#pool]
end

-- Bekleyen ödüller: claim başarılı ama teslim edilemediyse (çıkış, karakter yok, hata)

local function LoadPending()
	return util.JSONToTable(file.Read(PENDING_FILE, "DATA") or "") or {}
end

local function SavePending(pending)
	file.Write(PENDING_FILE, util.TableToJSON(pending, true))
end

-- TUZAK: özel (Grant fonksiyonlu) ödül JSON'a yazılamaz; adıyla saklanıp config'ten geri bulunur.
local function Serialize(reward)
	if (isfunction(reward.Grant)) then
		return {custom = reward.name or "?"}
	end

	return table.Copy(reward)
end

local function Deserialize(saved)
	if (!saved.custom) then return saved end

	for _, reward in ipairs(CFG.Rewards or {}) do
		if (isfunction(reward.Grant) and reward.name == saved.custom) then
			return reward
		end
	end
end

local function AddPending(sid, reward)
	local pending = LoadPending()

	pending[sid] = pending[sid] or {}
	table.insert(pending[sid], Serialize(reward))
	SavePending(pending)
end

local function DeliverPending(client)
	local sid = client:SteamID64()
	local pending = LoadPending()
	local list = pending[sid]

	if (!list or !IsReady(client)) then return false end

	local remaining, delivered = {}, {}

	for _, saved in ipairs(list) do
		local reward = Deserialize(saved)

		if (reward and IsValidReward(reward) and Grant(client, reward)) then
			delivered[#delivered + 1] = RewardName(reward)
		else
			remaining[#remaining + 1] = saved
		end
	end

	pending[sid] = #remaining > 0 and remaining or nil
	SavePending(pending)

	if (#delivered == 0) then return false end

	Log(Who(client, sid) .. " bekleyen ödülü aldı: " .. table.concat(delivered, ", "))
	Msg(client, "PendingDelivered", {reward = table.concat(delivered, ", ")})

	return true
end

local function Deliver(client, sid, reward)
	local tried = {}

	if (IsReady(client)) then
		for _ = 1, 3 do
			if (!reward) then break end

			if (Grant(client, reward)) then
				Log(Who(client, sid) .. " ödül aldı: " .. RewardName(reward))
				Msg(client, "Success", {reward = RewardName(reward)})

				return
			end

			Log("TESLİM EDİLEMEDİ, başka ödül deneniyor: " .. RewardName(reward))
			tried[reward] = true
			reward = Roll(tried)
		end
	end

	reward = reward or Roll()

	if (!reward) then
		Log("HATA: " .. Who(client, sid) .. " oyunu harcadı ama ödül havuzunda geçerli ödül yok!")
		Msg(client, "GiveFailed")
		return
	end

	AddPending(sid, reward)
	Log(Who(client, sid) .. " için ödül bekletiliyor: " .. RewardName(reward))
	Msg(client, "PendingSaved")
end

-- Oy linki

-- Aynı anda gelen istekler tek HTTP çağrısında birleşir.
local function FetchServer(callback)
	if (!KeyOK()) then return end

	if (VR.FetchQueue and CurTime() - (VR.FetchQueueAt or 0) < 15) then
		if (callback) then table.insert(VR.FetchQueue, callback) end
		return
	end

	VR.FetchQueue = {callback}
	VR.FetchQueueAt = CurTime()

	Request("GET", "/server", function(code, data)
		local queue = VR.FetchQueue

		VR.FetchQueue = nil

		if (code == 200 and isstring(data.vote_url) and string.StartWith(data.vote_url, "https://")) then
			VR.VoteURL = data.vote_url
		end

		for _, fn in ipairs(queue) do fn(code, data) end
	end)
end

local function SendVotePage(client, url)
	net.Start("gmtr_vr_open")
		net.WriteString(url)
	net.Send(client)

	Msg(client, "VoteOpen", {url = url})
end

function VR.OpenVotePage(client)
	if (VR.VoteURL) then
		SendVotePage(client, VR.VoteURL)
		return
	end

	if (!KeyOK()) then
		Msg(client, "NotConfigured")
		return
	end

	local sid = client:SteamID64()

	if ((VR.NextOpen[sid] or 0) > CurTime()) then
		Msg(client, "Wait")
		return
	end

	VR.NextOpen[sid] = CurTime() + COOLDOWN

	FetchServer(function()
		if (!IsValid(client)) then return end

		if (VR.VoteURL) then
			SendVotePage(client, VR.VoteURL)
		else
			Msg(client, "ApiError")
		end
	end)
end

-- Ödül alma

function VR.Claim(client)
	if (!IsValid(client) or client:IsBot()) then return end

	if (!KeyOK()) then
		Msg(client, "NotConfigured")
		return
	end

	local sid = client:SteamID64()

	if ((VR.Busy[sid] or 0) > CurTime()) then return end

	if ((VR.NextUse[sid] or 0) > CurTime()) then
		Msg(client, "Wait")
		return
	end

	if (!IsReady(client)) then
		Msg(client, "NoCharacter")
		return
	end

	VR.NextUse[sid] = CurTime() + COOLDOWN

	if (DeliverPending(client)) then return end

	local reward = Roll()

	if (!reward) then
		Log("HATA: ödül havuzunda geçerli ödül yok (sh_config.lua)")
		Msg(client, "PoolEmpty")
		return
	end

	VR.Busy[sid] = CurTime() + 30
	Msg(client, "Checking")

	Request("POST", "/votes/" .. sid .. "/claim", function(code, data)
		VR.Busy[sid] = nil

		if (code == 200) then
			if (IsValid(client)) then
				Deliver(client, sid, reward)
			else
				AddPending(sid, reward)
				Log(sid .. " claim sonrası çıktı, ödül bekletiliyor: " .. RewardName(reward))
			end
		elseif (code == 404) then
			Msg(client, "NotVoted")
		elseif (code == 409) then
			Msg(client, "AlreadyClaimed")
		elseif (code == 429) then
			Msg(client, "RateLimited")
		else
			Log("API hatası (" .. code .. ") " .. Who(client, sid) .. ": " .. tostring(data.detail))
			Msg(client, "ApiError")
		end
	end)
end

-- Helix yoksa sohbet komutları

if (!ix) then
	hook.Add("PlayerSay", "gmtr_votereward", function(client, text)
		local command = string.match(text, "^[/!](%S+)")

		if (!command) then return end

		command = string.lower(command)

		local function Matches(name, aliases)
			if (command == name) then return true end

			for _, alias in ipairs(aliases or {}) do
				if (command == string.lower(alias)) then return true end
			end
		end

		if (Matches("reward", CFG.Aliases.Reward)) then
			VR.Claim(client)
			return ""
		elseif (Matches("oyver", CFG.Aliases.Vote)) then
			VR.OpenVotePage(client)
			return ""
		end
	end)
end

-- Giriş hatırlatması ve bekleyen ödül teslimi

local function OnPlayerReady(client)
	if (!IsValid(client) or client:IsBot()) then return end

	local sid = client:SteamID64()

	timer.Simple(1, function()
		if (IsValid(client)) then DeliverPending(client) end
	end)

	if (!CFG.RemindOnJoin or !KeyOK() or VR.Reminded[sid]) then return end

	VR.Reminded[sid] = true

	timer.Simple(CFG.RemindDelay or 20, function()
		if (!IsValid(client)) then return end

		Request("GET", "/votes/" .. sid, function(code, data)
			if (code != 200) then return end

			if (!data.voted) then
				Msg(client, "RemindNotVoted")
			elseif (!data.claimed) then
				Msg(client, "RemindUnclaimed")
			end
		end)
	end)
end

if (ix) then
	hook.Add("PlayerLoadedCharacter", "gmtr_votereward", OnPlayerReady)
else
	hook.Add("PlayerInitialSpawn", "gmtr_votereward", function(client)
		timer.Simple(5, function() OnPlayerReady(client) end)
	end)
end

hook.Add("PlayerDisconnected", "gmtr_votereward", function(client)
	local sid = client:SteamID64()

	VR.Reminded[sid] = nil
	VR.NextUse[sid] = nil
	VR.NextOpen[sid] = nil
	VR.Busy[sid] = nil
end)

-- TUZAK: HTTP ilk tick'ten önce çalışmaz.
timer.Simple(5, function() FetchServer() end)

-- Yönetici denetimi: anahtar ve havuz durumu

concommand.Add("gmtr_vr_status", function(client)
	if (IsValid(client) and !client:IsSuperAdmin()) then return end

	local function Print(text)
		if (IsValid(client)) then client:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end
	end

	Print("[gmtr_votereward] Çerçeve: " .. (ix and "Helix" or DarkRP and "DarkRP" or "düz"))

	for _, reward in ipairs(CFG.Rewards or {}) do
		local bValid = IsValidReward(reward)

		Print(string.format("  [%s] %s (ağırlık %s)", bValid and "OK" or "GEÇERSİZ",
			bValid and RewardName(reward) or tostring(reward.type), tostring(reward.weight)))
	end

	if (!KeyOK()) then
		Print("[gmtr_votereward] API anahtarı yok ya da gmtr_ ile başlamıyor (sv_config.lua).")
		return
	end

	FetchServer(function(code, data)
		if (code == 200) then
			Print(string.format("[gmtr_votereward] Anahtar geçerli: %s | sıra %s | bu ay %s oy | %s",
				tostring(data.name), tostring(data.rank), tostring(data.votes_month), tostring(data.vote_url)))
		else
			Print("[gmtr_votereward] Anahtar reddedildi (" .. code .. "): " .. tostring(data.detail))
		end
	end)
end)
