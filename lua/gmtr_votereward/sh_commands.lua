-- gmtr_votereward komutları: Helix varsa ix.command, yoksa sohbet (sv_votereward.lua)
if (!ix or !ix.command or !ix.command.Add) then return end

local CFG = GMTR_VR.Config

ix.command.Add("reward", {
	alias = CFG.Aliases.Reward,
	description = "gmod.tr'de sunucuya verdiğin oyun ödülünü alırsın.",
	OnRun = function(self, client)
		GMTR_VR.Claim(client)
	end
})

ix.command.Add("oyver", {
	alias = CFG.Aliases.Vote,
	description = "gmod.tr oy sayfasını açar.",
	OnRun = function(self, client)
		GMTR_VR.OpenVotePage(client)
	end
})
