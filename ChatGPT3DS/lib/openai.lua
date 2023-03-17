local https = require("https")

OpenAI = {}

OpenAI.API_KEY = ""
OpenAI.API_URL = "https://api.openai.com/v1/"

-- Chat Completion Settings
OpenAI.chatModel = "gpt-3.5-turbo"
OpenAI.temperature = 1.0
OpenAI.top_p = 1.0
OpenAI.presence_penalty = 0.0
OpenAI.frequency_penalty = 0.0

-- Image Generation Settings
OpenAI.IMAGE_SIZES = {"256x256", "512x512", "1024x1024"}
OpenAI.image_size = 1

function OpenAI.ChatMessageTableToString(messages)
    messageString = "["
    for i, message in ipairs(messages) do
        messageString = messageString .. string.format("{\"role\": \"%s\", \"content\": \"%s\"}", message.role, message.content)
        if i ~= #messages then
            messageString = messageString .. ","
        end
    end
    messageString = messageString .. "]"
    return messageString
end

function OpenAI.ChatCompletion(messages, model)
    model = model or OpenAI.chatModel
    OpenAI.call = string.format(
        [[{
        "model": "%s",
        "messages": %s,
        "temperature": %f,
        "top_p": %f,
        "presence_penalty": %f,
        "frequency_penalty": %f
        }]],
        model,
        OpenAI.ChatMessageTableToString(messages),
        OpenAI.temperature,
        OpenAI.top_p,
        OpenAI.presence_penalty,
        OpenAI.frequency_penalty
    )
    return OpenAI._make_call(OpenAI.API_URL .. "chat/completions")
end

function OpenAI.ImageGeneration(prompt)
    OpenAI.call = string.format(
        [[{
            "prompt": "%s",
            "size": "%s",
            "response_format": "b64_json"
        }]],
        prompt,
        OpenAI.IMAGE_SIZES[OpenAI.image_size]
    )
    return OpenAI._make_call(OpenAI.API_URL .. "images/generations")
end

function OpenAI._make_call(url)
    return https.request(url,
    {
        method = "post",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = string.len(OpenAI.call),
            ["Authorization"] = "Bearer " .. OpenAI.API_KEY
        },
        data = OpenAI.call
    })
end

return OpenAI