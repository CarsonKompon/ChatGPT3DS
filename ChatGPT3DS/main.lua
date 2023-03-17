---@diagnostic disable: duplicate-set-field
require "lib.lovebrew-pc"
require "lib.text-draw"
require "lib.openai"
json = require("lib.json")
utf8 = require("utf8")
pngImage = require("lib.png")

-- PC Initialization
if LovebrewPC.CONSOLE_NAME == "PC" then
    love.window.setMode(400, 480)
end

local SCREEN_WIDTH = 400
local SCREEN_HEIGHT = 240
local DISPLAY_STATE = "text"
local STATE = "menu"

local HAS_IMAGE_GEN = true

loadedApiKey, apiKeySize = love.filesystem.read("api_key.txt")
if loadedApiKey ~= nil then
    OpenAI.API_KEY = loadedApiKey
end

local systemMessage = "You are a helpful chatbot."
local lastQuestion = ""
local questionResponse = ""
local lastMessages = {}
local lastImage = nil
local estimatedCost = ""

local menuItems = {
    { "Ask Question", function() AskQuestion() end },
    { "Set System Message", function() SetSystemMessage() end },
    { "Generate Image", function() GenerateImage() end },
    { "Set API Key", function() SetAPIKey() end },
    { "Settings", function() Settings() end }
}
if not HAS_IMAGE_GEN then
    menuItems[2] = { "Set System Message", function() SetSystemMessage() end }
end

local settingsItems = {
    { "Chat Model", function() SetChatModel(-1) end, function() SetChatModel(1) end, function() return OpenAI.chatModel end},
    { "Temperature", function() SetTemperature(-0.1) end, function() SetTemperature(0.1) end, function() return OpenAI.temperature end},
    { "Top P", function() SetTopP(-0.05) end, function() SetTopP(0.05) end, function() return OpenAI.top_p end},
    { "Presence Penalty", function() SetPresence(-0.1) end, function() SetPresence(0.1) end, function() return OpenAI.presence_penalty end},
    { "Frequency Penalty", function() SetFrequency(-0.1) end, function() SetFrequency(0.1) end, function() return OpenAI.frequency_penalty end},
    { "Reset to Defaults", function() ResetSettings() end},
    { "Back", function() MainMenu() end}
}
local menuSelection = 1

local chatModel = 1
local CHAT_MODELS = {"gpt-3.5-turbo", "gpt-4"}
local CHAT_COSTS = {0.002, 0.03} -- Cost per 1K tokens

local keyboardTrigger = false

font = nil
response = nil
function love.load()
    -- Eventually load real fonts here
    font = love.graphics.getFont()
end

function love.draw(screen)
    if LovebrewPC.CONSOLE_NAME == "PC" then
        love.graphics.push()
        love.graphics.translate((400 - 320) / 2, 240)
        draw_bottom_screen()
        love.graphics.pop()
        draw_top_screen(0)
    else
        if screen == "bottom" then
            draw_bottom_screen()
        else
            local depth = -love.graphics.get3DDepth()
            if screen == "right" then
                depth = -depth
            end
            draw_top_screen(depth)
        end
    end

    CheckKeyboardTrigger()
end

function draw_top_screen(depth)
    SCREEN_WIDTH = 400
    SCREEN_HEIGHT = 240

    -- Fill background
    love.graphics.setColor(255, 255, 255, 255)
    love.graphics.rectangle("fill", 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT)

    -- Draw Title
    local textDepth = 4 * depth
    TextDraw.DrawTextCentered("ChatGPT3DS", SCREEN_WIDTH/2 - textDepth, 16, {0, 0, 0, 255}, font, 1)
    textDepth = 2 * depth
    TextDraw.DrawTextCentered("by Carson Kompon", SCREEN_WIDTH/2 - textDepth, 34, {0, 0, 0, 255}, font, 0.5)
    
    -- Draw Menus
    if STATE == "settings" then
        -- Draw Settings Menu
        draw_menu(settingsItems, 0.6)
        -- Draw Disclaimer
        TextDraw.DrawTextCentered("OpenAI recommends to change either Temperature or Top P, but not both at once.", SCREEN_WIDTH/2, SCREEN_HEIGHT - 16, {0.4, 0.4, 0.4, 255}, font, 0.4)
    else
        -- Draw Main Menu
        draw_menu(menuItems, 0.9, 70)
        -- Draw Last Question
        if lastQuestion ~= "" then
            TextDraw.DrawTextCentered('"' .. lastQuestion .. '"', SCREEN_WIDTH/2, SCREEN_HEIGHT - 22, {0.4, 0.4, 0.4, 255}, font, 0.5)
        end
    end

end

function draw_bottom_screen()
    SCREEN_WIDTH = 320
    SCREEN_HEIGHT = 240

    -- Fill background
    love.graphics.setColor(255, 255, 255, 255)
    love.graphics.rectangle("fill", 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT)

    if STATE == "image" then
        TextDraw.DrawTextCentered("Generating...", SCREEN_WIDTH/2, SCREEN_HEIGHT/2, {0, 0, 0, 255}, font, 1)
        TextDraw.DrawTextCentered("(This can take a while...)", SCREEN_WIDTH/2, SCREEN_HEIGHT/2 + 18, {0.4, 0.4, 0.4, 255}, font, 0.5)
    elseif STATE == "ask" or STATE == "continue" then
        TextDraw.DrawTextCentered("Thinking...", SCREEN_WIDTH/2, SCREEN_HEIGHT/2, {0, 0, 0, 255}, font, 1)
    elseif DISPLAY_STATE == "text" then
        local wrappedResponse = TextDraw.GetWrappedText(questionResponse, font, SCREEN_WIDTH - 24, 0.5)
        TextDraw.DrawTextCentered(wrappedResponse, SCREEN_WIDTH/2, 12, {0, 0, 0, 255}, font, 0.5)
    elseif DISPLAY_STATE == "image" then
        if lastImage ~= nil then
            local targetSize = math.min(SCREEN_WIDTH, SCREEN_HEIGHT)
            local scale = targetSize / lastImage:getWidth()
            love.graphics.draw(lastImage, (SCREEN_WIDTH-lastImage:getWidth()*scale)/2, (SCREEN_HEIGHT-lastImage:getHeight()*scale)/2, 0, scale, scale)
        end
    end

    -- Draw estimated cost
    if estimatedCost ~= "" then
        TextDraw.DrawTextCentered(estimatedCost, SCREEN_WIDTH/2, SCREEN_HEIGHT - 12, {0.4, 0.4, 0.4, 255}, font, 0.4)
    end
end

function draw_menu(items, scale, menuY)
    scale = scale or 1
    menuY = menuY or 76
    for i=1,#items do
        local menuItem = items[i]
        local menuItemText = menuItem[1]
        if #menuItem == 4 then
            local text = menuItem[4]()
            if type(text) == "string" then
                menuItemText = menuItemText .. ": " .. text
            else
                menuItemText = menuItemText .. ": " .. string.format("%.2f", text)
            end
        end
        local menuItemColor = {0, 0, 0, 255}
        if i == menuSelection then
            menuItemColor = {255, 0, 0, 255}
            menuItemText = "> " .. menuItemText .. " <"
        end
        TextDraw.DrawTextCentered(menuItemText, SCREEN_WIDTH/2, menuY, menuItemColor, font, scale)
        menuY = menuY + 32*scale
    end
end

function love.gamepadpressed(joystick, button)
    local _items = menuItems
    if STATE == "settings" then _items = settingsItems end
    if button == "dpup" then
        menuSelection = menuSelection - 1
        if menuSelection < 1 then
            menuSelection = #_items
        end
    elseif button == "dpdown" then
        menuSelection = menuSelection + 1
        if menuSelection > #_items then
            menuSelection = 1
        end
    elseif button == "dpleft" then
        if #_items[menuSelection] == 4 then
            _items[menuSelection][2]()
        end
    elseif button == "dpright" then
        if #_items[menuSelection] == 4 then
            _items[menuSelection][3]()
        end
    elseif button == "a" then
        if #_items[menuSelection] == 2 then
            _items[menuSelection][2]()
        end
    elseif button == "b" then
        if STATE == "settings" then
            MainMenu()
        end
    elseif button == "start" then
        love.event.quit()
    end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
    if STATE == "menu" and DISPLAY_STATE == "text" and questionResponse ~= "" then
        STATE = "continue"
        keyboardTrigger = true
    end
end

function CheckKeyboardTrigger()
    if keyboardTrigger then
        if STATE == "api" then
            love.keyboard.setTextInput({hint = "Enter OpenAI API Key"})
        elseif STATE == "image" then
            if LovebrewPC.CONSOLE_NAME == "PC" then
                love.textinput("nintendo 3ds") -- DEBUG PURPOSES
            else
                love.keyboard.setTextInput({hint = "Enter Image Prompt"})
            end
        elseif STATE == "system" then
            love.keyboard.setTextInput({hint = systemMessage})
        elseif STATE == "ask" then
            if LovebrewPC.CONSOLE_NAME == "PC" then
                love.textinput("haiku about nintendo 3ds") -- DEBUG PURPOSES
            else
                love.keyboard.setTextInput({hint = "Ask a question..."})
            end
        elseif STATE == "continue" then
            love.keyboard.setTextInput({hint = "Continue conversation..."})
        end
        keyboardTrigger = false
    end
end

function love.textinput(text)
    if text ~= "" then
        if STATE == "api" then
            OpenAI.API_KEY = text
            love.filesystem.write("api_key.txt", text)
        elseif STATE == "system" then
            systemMessage = text
        elseif STATE == "ask" then
            lastQuestion = text
            estimatedCost = ""
            lastMessages = {
                { role = "system", content = systemMessage },
                { role = "user", content = lastQuestion }
            }
            code, body, headers = OpenAI.ChatCompletion(lastMessages)
            j = json.parse(body)
            if type(j.choices) == "table" then
                questionResponse = j.choices[1].message.content
                estimatedCost = "Estimated Cost: $" .. string.format("%.6f", j.usage.total_tokens / 1000 * CHAT_COSTS[chatModel])
            else
                questionResponse = "Error: " .. body
                estimatedCost = ""
            end
        elseif STATE == "image" then
            lastQuestion = text
            estimatedCost = ""
            code, body, headers = OpenAI.ImageGeneration(lastQuestion)
            questionResponse = body
            -- find the position of `"b64_json": ` in the string
            b64tag = '"b64_json":'
            local b64_json_start = string.find(body, b64tag, 1, true)
            if b64_json_start ~= nil then
                -- find the position of the first quote after b64_json_start
                local firstQuote = string.find(body, '"', b64_json_start + string.len(b64tag) + 1, true)
                -- find the position of the second quote after the first
                local secondQuote = string.find(body, '"', firstQuote + 1, true)
                -- get the substring between the two quotes
                b64 = string.sub(body, firstQuote + 1, secondQuote - 1)
                -- decode the base64 string
                decoded = love.data.decode("string", "base64", b64)

                imageData = love.image.newImageData(256, 256, "rgba8")

                -- save the decoded string to a file
                pngFileName = "dalle.png"
                love.filesystem.write(pngFileName, decoded)

                rgba_table, img_width, img_height = pngImage(pngFileName)
                for y = 1, img_height do
                    for x = 1, img_width do
                        local index = (y - 1) * img_width + x
                        local pixel = rgba_table[index]
                        local r = pixel[1]
                        local g = pixel[2]
                        local b = pixel[3]
                        local a = pixel[4]
                        imageData:setPixel(x - 1, y - 1, r/255, g/255, b/255, a/255)
                    end
                end

                lastImage = love.graphics.newImage(imageData)

                estimatedCost = "Estimated Cost: $0.016"
            else
                DISPLAY_STATE = "text"
                questionResponse = "Error: " .. body
                estimatedCost = ""
            end
        elseif STATE == "continue" then
            lastQuestion = text
            estimatedCost = ""
            table.insert(lastMessages, { role = "assistant", content = questionResponse })
            table.insert(lastMessages, { role = "user", content = lastQuestion })
            code, body, headers = OpenAI.ChatCompletion(lastMessages)
            j = json.parse(body)
            if type(j.choices) == "table" then
                questionResponse = j.choices[1].message.content
                estimatedCost = "Estimated Cost: $" .. string.format("%.6f", j.usage.total_tokens / 1000 * CHAT_COSTS[chatModel])
            else
                questionResponse = "Error: " .. body
                estimatedCost = ""
            end
        end
    end
    STATE = "menu"
end

function CheckAPI()
    local hasApi = OpenAI.API_KEY ~= ""
    if not hasApi then
        questionResponse = "You must enter your OpenAI API Key before making any requests."
    end
    return hasApi
end

function AskQuestion()
    if not CheckAPI() then return end
    STATE = "ask"
    DISPLAY_STATE = "text"
    keyboardTrigger = true

end

function GenerateImage()
    if not CheckAPI() then return end
    STATE = "image"
    DISPLAY_STATE = "image"
    keyboardTrigger = true
end

function SetSystemMessage()
    if not CheckAPI() then return end
    STATE = "system"
    DISPLAY_STATE = "text"
    keyboardTrigger = true
end

function SetAPIKey()
    STATE = "api"
    keyboardTrigger = true
end

function MainMenu()
    STATE = "menu"
    menuSelection = #menuItems
end

function Settings()
    STATE = "settings"
    menuSelection = 1
end

function SetChatModel(model)
    chatModel = chatModel + model
    if chatModel < 1 then chatModel = 1 end
    if chatModel > #CHAT_MODELS then chatModel = #CHAT_MODELS end
    OpenAI.chatModel = CHAT_MODELS[chatModel]
end

function SetTemperature(temperature)
    OpenAI.temperature = OpenAI.temperature + temperature
    if OpenAI.temperature < 0 then OpenAI.temperature = 0 end
    if OpenAI.temperature > 2 then OpenAI.temperature = 2 end
end

function SetTopP(top_p)
    OpenAI.top_p = OpenAI.top_p + top_p
    if OpenAI.top_p < 0 then OpenAI.top_p = 0 end
    if OpenAI.top_p > 1 then OpenAI.top_p = 1 end
end

function SetPresence(presence)
    OpenAI.presence_penalty = OpenAI.presence_penalty + presence
    if OpenAI.presence_penalty < -2 then OpenAI.presence_penalty = -2 end
    if OpenAI.presence_penalty > 2 then OpenAI.presence_penalty = 2 end
end

function SetFrequency(frequency)
    OpenAI.frequency_penalty = OpenAI.frequency_penalty + frequency
    if OpenAI.frequency_penalty < -2 then OpenAI.frequency_penalty = -2 end
    if OpenAI.frequency_penalty > 2 then OpenAI.frequency_penalty = 2 end
end

function ResetSettings()
    OpenAI.temperature = 1.0
    OpenAI.top_p = 1.0
    OpenAI.presence_penalty = 0.0
    OpenAI.frequency_penalty = 0.0
end