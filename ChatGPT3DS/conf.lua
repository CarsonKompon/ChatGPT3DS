require("lib.lovebrew-pc")

function love.conf(t)
	if LovebrewPC.CONSOLE_NAME == "PC" then
		t.console = true
	end
end