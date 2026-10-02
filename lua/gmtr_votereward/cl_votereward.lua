-- gmtr_votereward istemci: sohbet mesajı ve oy sayfası
local PREFIX_COLOR = Color(200, 0, 0)
local TEXT_COLOR = Color(235, 235, 235)

net.Receive("gmtr_vr_msg", function()
	chat.AddText(PREFIX_COLOR, "[gmod.tr] ", TEXT_COLOR, net.ReadString())
end)

net.Receive("gmtr_vr_open", function()
	local url = net.ReadString()

	if (!string.StartWith(url, "https://")) then return end

	SetClipboardText(url)
	gui.OpenURL(url)
end)
