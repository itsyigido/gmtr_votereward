-- gmtr_votereward ayarları (API anahtarı sv_config.lua'da).
GMTR_VR.Config = GMTR_VR.Config or {}
local CFG = GMTR_VR.Config

-- /reward ve /oyver sabit; buraya eş anlamlılarını yaz (DarkRP'de ! ile de çalışır)
CFG.Aliases = {
	Reward = {"odul"},
	Vote = {"oyver"},
}

-- Oyuncu girince oy durumunu hatırlat (oturum başına bir kez)
CFG.RemindOnJoin = true 
CFG.RemindDelay = 20 -- Kaç saniye sonra hatırlatsın

--[[
	Ödül havuzu: her oyda BİR ödül çekilir, şansı = weight / toplam weight.
	Helix:
	  money    miktar                            Karakterin parası
	  item     item = "<uniqueID>", miktar       Envantere eklenir (doluysa yere düşer)
	DarkRP:
	  money    amount                            Oyuncunun parası
	  weapon   class = "<silah sınıfı>"          Direkt eline verilir (1-6 slotları); ölünce gider
	  shipment shipment = "<F4'teki ad>", sayı  Koli önüne düşer (count boşsa kolinin kendi adedi)
	Her ikisinde:
	  command  command = "...", name             Sunucu konsolunda çalışır; {steamid} {steamid64} {userid} {name}
	  Özel ödül: {name = "...", weight = 5, Grant = function(client, character) return true end}
	Her ödülde name = "..." ile görünen ad değiştirilebilir. Sunucu gamemode'sine uymayan ödül atlanır ve kimseye verilmez.
]]
CFG.Rewards = {
	{type = "money", amount = 29, weight = 79.9},
	{type = "money", amount = 100, weight = 20},
	{type = "item", item = "kasa_spin_kutusu", amount = 1, weight = 0.1},
}
