-- gmtr_votereward yükleyicisi: gmod.tr oyu karşılığı /reward ödülü.
GMTR_VR = GMTR_VR or {}

local DIR = "gmtr_votereward/"

local function Shared(name)
	if (SERVER) then AddCSLuaFile(DIR .. name) end
	include(DIR .. name)
end

local function Client(name)
	if (SERVER) then AddCSLuaFile(DIR .. name) else include(DIR .. name) end
end

local function Server(name)
	if (SERVER) then include(DIR .. name) end
end

timer.Simple(0, function()
	Shared("sh_config.lua")
	Shared("sh_commands.lua")
	Client("cl_votereward.lua")
	Server("sv_config.lua")
	Server("sv_votereward.lua")
end)
