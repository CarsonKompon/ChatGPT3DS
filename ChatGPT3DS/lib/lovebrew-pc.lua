

LovebrewPC = {}
    
-- Global Variables
LovebrewPC.CONSOLE_NAME = love._console_name or "PC"

function LovebrewPC.LoadImage(name)
    if LovebrewPC.CONSOLE_NAME == "3DS" then
        return love.graphics.newImage( name .. ".t3x")
    else
        return love.graphics.newImage(name .. ".png")
    end
end

return LovebrewPC