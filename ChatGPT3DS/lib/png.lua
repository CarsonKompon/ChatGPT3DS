local deflate = require("lib.deflatelua")

local function read_byte(file)
    local byte = file:read(1)
    return byte and string.byte(byte) or nil
end

local function read_int(file)
    local a, b, c, d = read_byte(file), read_byte(file), read_byte(file), read_byte(file)
    if not (a and b and c and d) then
        return nil
    end
    return a * 2^24 + b * 2^16 + c * 2^8 + d
end

local function read_chunk(file)
    local length = read_int(file)
    if not length then
        return nil, nil
    end
    local chunk_type = file:read(4)
    local data = file:read(length)
    local crc = read_int(file)
    return chunk_type, data
end

local function read_int_from_string(str, start)
    local a, b, c, d = string.byte(str, start, start + 3)
    return a * 2^24 + b * 2^16 + c * 2^8 + d
end

local function paeth_predictor(a, b, c)
    local p = a + b - c
    local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
    if pa <= pb and pa <= pc then
        return a
    elseif pb <= pc then
        return b
    else
        return c
    end
end

local function unfilter_scanline(filter_type, scanline, previous_scanline, bpp)
    local result = {}
    for i = 1, #scanline do
        local x = scanline[i]
        local a = i > bpp and result[i - bpp] or 0
        local b = previous_scanline and previous_scanline[i] or 0
        local c = (i > bpp and previous_scanline) and previous_scanline[i - bpp] or 0
        if filter_type == 1 then
            x = x + a
        elseif filter_type == 2 then
            x = x + b
        elseif filter_type == 3 then
            x = x + math.floor((a + b) / 2)
        elseif filter_type == 4 then
            x = x + paeth_predictor(a, b, c)
        end
        result[i] = x % 256
    end
    return result
end

local function parse_png(filename)
    local file = love.filesystem.newFile(filename)
    assert(file:open("r"), "Cannot read the file")
    assert(file:read(8) == "\137PNG\r\n\26\n", "Not a PNG file")

    local width, height, bit_depth, color_type, bpp
    local idat_data = {}
    while true do
        local chunk_type, data = read_chunk(file)
        if not chunk_type then
            break
        end
        if chunk_type == "IHDR" then
            width = read_int_from_string(data, 1)
            height = read_int_from_string(data, 5)
            bit_depth, color_type = string.byte(data, 9, 10)
            bpp = math.ceil(bit_depth * (color_type == 6 and 4 or 3) / 8)
        elseif chunk_type == "IDAT" then
            idat_data[#idat_data + 1] = data
        elseif chunk_type == "IEND" then
            break
        end
    end
    file:close()

    local output = {}
    deflate.inflate_zlib {
        input = table.concat(idat_data),
        output = function(byte)
            output[#output+1] = string.char(byte)
        end,
        disable_crc = true
    }
    local data = table.concat(output)

    local scanlines = {}
    local pos = 1
    for y = 1, height do
        local filter_type = data:byte(pos)
        pos = pos + 1
        local scanline = {}
        for _ = 1, width * bpp do
            scanline[#scanline + 1] = data:byte(pos)
            pos = pos + 1
        end
        scanlines[y] = unfilter_scanline(filter_type, scanline, scanlines[y - 1], bpp)
    end

    local rgba_table = {}
    for y = 1, height do
        local scanline = scanlines[y]
        for x = 1, width do
            local r, g, b, a
            if color_type == 2 then
                r, g, b = scanline[(x - 1) * bpp + 1], scanline[(x - 1) * bpp + 2], scanline[(x - 1) * bpp + 3]
                a = 255
            elseif color_type == 6 then
                r, g, b, a = scanline[(x - 1) * bpp + 1], scanline[(x - 1) * bpp + 2], scanline[(x - 1) * bpp + 3], scanline[(x - 1) * bpp + 4]
            end
            rgba_table[(y - 1) * width + x] = {r, g, b, a}
        end
    end

    return rgba_table, width, height
end

return parse_png