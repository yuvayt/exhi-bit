-- Inlined helpers

local function defaultFolder()
    local folderPath = app.fs.userDocsPath
    local appPrefs <const> = app.preferences
    if appPrefs then
        local fileSelectPrefs <const> = appPrefs.file_selector
        if fileSelectPrefs then
            local currFolder <const> = fileSelectPrefs.current_folder
            if app.fs.isDirectory(currFolder) then
                folderPath = currFolder
            end
        end
    end
    local pathSep <const> = app.fs.pathSeparator
    if string.sub(folderPath, #folderPath) ~= pathSep then
        folderPath = folderPath .. pathSep
    end
    return folderPath
end

local function getPalette(frame, palettes)
    local lenPalettes <const> = #palettes
    if lenPalettes <= 0 then
        local emptyPal <const> = Palette(1)
        emptyPal:setColor(0, Color { r = 0, g = 0, b = 0, a = 0 })
        return emptyPal
    end
    local idx = 1
    local typeFrObj <const> = type(frame)
    if typeFrObj == "number"
        and math.type(frame) == "integer" then
        idx = frame
    elseif typeFrObj == "userdata" then
        ---@diagnostic disable-next-line: undefined-field
        idx = frame.frameNumber
    end
    if idx > lenPalettes then idx = 1 end
    return palettes[idx]
end

local function aseColorToHex(c)
    return (c.alpha << 0x18)
        | (c.blue << 0x10)
        | (c.green << 0x08)
        | c.red
end

local function stringToCharArr(str)
    ---@type string[]
    local chars <const> = {}
    local lenChars = 0
    local utf8codes <const> = utf8.codes
    local utf8char <const> = utf8.char
    for _, c in utf8codes(str) do
        lenChars = lenChars + 1
        chars[lenChars] = utf8char(c)
    end
    return chars
end

local function trimCharsFinal(chars)
    local tr <const> = table.remove
    while chars[#chars] == ' ' do tr(chars) end
    return chars
end

local function trimCharsInitial(chars)
    local tr <const> = table.remove
    while chars[1] == ' ' do tr(chars, 1) end
    return chars
end

local function validateFilename(filename)
    local fileChars <const> = stringToCharArr(filename)
    trimCharsInitial(fileChars)
    trimCharsFinal(fileChars)
    local len <const> = #fileChars
    local i = 0
    while i < len do
        i = i + 1
        local char <const> = fileChars[i]
        if char == '\\' or char == '`'
            or char == '/' or char == ':'
            or char == '*' or char == '?'
            or char == '"' or char == '\''
            or char == '<' or char == '>'
            or char == '|' or char == '.' then
            fileChars[i] = '_'
        end
    end
    return table.concat(fileChars)
end

-- Constants

local defaults <const> = {
    iconName     = "",
    roundPercent = 0,
}

-- Core utilities

---@param aIdx integer
---@param bIdx integer
---@param imgWidth integer
---@return boolean
local function comparator(aIdx, bIdx, imgWidth)
    local ay <const> = aIdx // imgWidth
    local by <const> = bIdx // imgWidth
    if ay < by then return true end
    if ay > by then return false end
    return (aIdx % imgWidth) < (bIdx % imgWidth)
end

---@param webHex integer 0x00RRGGBB
---@return string "#RGB" or "#RRGGBB"
local function toShortHex(webHex)
    local r <const> = (webHex >> 16) & 0xff
    local g <const> = (webHex >> 8) & 0xff
    local b <const> = webHex & 0xff
    if (r >> 4) == (r & 0xf)
        and (g >> 4) == (g & 0xf)
        and (b >> 4) == (b & 0xf) then
        return string.format("#%x%x%x", r >> 4, g >> 4, b >> 4)
    end
    return string.format("#%06X", webHex)
end

---@param s string
---@return string
local function xmlEscape(s)
    s = string.gsub(s, "&", "&amp;")
    s = string.gsub(s, "<", "&lt;")
    s = string.gsub(s, ">", "&gt;")
    s = string.gsub(s, "\"", "&quot;")
    return s
end

---Returns a fill-opacity attribute string, or "" when fully opaque.
---Uses 2 decimal places with trailing zero stripped.
---@param alpha integer 0–255
---@return string
local function opacityAttr(alpha)
    if alpha >= 255 then return "" end
    local s <const> = string.gsub(
        string.format("%.2f", alpha / 255.0), "0$", "")
    return " fill-opacity=\"" .. s .. "\""
end

---Returns a lowercase, hyphen-separated Freedesktop-compatible icon name.
---@param dlgName string value from dialog entry (may be "")
---@param sprite Sprite active Aseprite sprite
---@return string
local function resolveIconName(dlgName, sprite)
    local raw
    if dlgName and #dlgName > 0 then
        raw = dlgName
    else
        raw = app.fs.fileTitle(sprite.filename)
        if not raw or #raw == 0 then raw = "icon" end
    end
    raw = validateFilename(raw)
    raw = string.lower(raw)
    raw = string.gsub(raw, "[ _]+", "-")
    raw = string.gsub(raw, "^%-+", "")
    raw = string.gsub(raw, "%-+$", "")
    if #raw == 0 then raw = "icon" end
    return raw
end

-- Rectangle merge (roundPercent == 0)

---Greedy covering set of non-overlapping axis-aligned rectangles for one color.
---@param idxArr integer[] flat pixel indices (y*imgWidth+x, 0-based); sorted in-place
---@param imgWidth integer
---@param imgHeight integer
---@return table[] rects list of {x,y,w,h}
local function mergeRectsForColor(idxArr, imgWidth, imgHeight)
    -- Step 1: sort ascending (= top-left to bottom-right scan order).
    table.sort(idxArr)

    -- Step 2: horizontal merge.
    ---@type table[]
    local strips <const> = {}
    local lenStrips = 0
    local curX = -1
    local curY = -1
    local curW = 0
    local lenIdx <const> = #idxArr
    local i = 0
    while i < lenIdx do
        i = i + 1
        local idx <const> = idxArr[i]
        local row <const> = idx // imgWidth
        local col <const> = idx % imgWidth
        if row == curY and col == curX + curW then
            curW = curW + 1
        else
            if curW > 0 then
                lenStrips = lenStrips + 1
                strips[lenStrips] = { x = curX, y = curY, w = curW, h = 1 }
            end
            curX = col
            curY = row
            curW = 1
        end
    end
    if curW > 0 then
        lenStrips = lenStrips + 1
        strips[lenStrips] = { x = curX, y = curY, w = curW, h = 1 }
    end

    -- Step 3: sort strips by (x, w, y) to group vertically-mergeable strips.
    table.sort(strips, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        if a.w ~= b.w then return a.w < b.w end
        return a.y < b.y
    end)

    -- Step 4: vertical merge.
    ---@type table[]
    local rects <const> = {}
    local lenRects = 0
    if lenStrips > 0 then
        local s0 <const> = strips[1]
        local curRect = { x = s0.x, y = s0.y, w = s0.w, h = 1 }
        local j = 1
        while j < lenStrips do
            j = j + 1
            local s <const> = strips[j]
            if s.x == curRect.x and s.w == curRect.w
                and s.y == curRect.y + curRect.h then
                curRect.h = curRect.h + 1
            else
                lenRects = lenRects + 1
                rects[lenRects] = curRect
                curRect = { x = s.x, y = s.y, w = s.w, h = 1 }
            end
        end
        lenRects = lenRects + 1
        rects[lenRects] = curRect
    end

    return rects
end

---Converts a list of {x,y,w,h} rects to a compact SVG path d= string.
---@param rects table[]
---@return string
local function rectsToPathData(rects)
    local lenRects <const> = #rects
    if lenRects == 0 then return "" end
    ---@type string[]
    local parts <const> = {}
    local i = 0
    while i < lenRects do
        i = i + 1
        local r <const> = rects[i]
        parts[i] = string.format("M%d %dh%dv%dh-%dZ",
            r.x, r.y, r.w, r.h, r.w)
    end
    return table.concat(parts, "")
end

-- Per-pixel rounded rects (roundPercent > 0)

---Returns concatenated <rect> elements (no fill — handled by parent <g>).
---@param idxArr integer[] flat pixel indices for one color
---@param imgWidth integer
---@param rxStr string pre-formatted rx value (e.g. "0.5", "0.25")
---@return string
local function pixelsToRoundedRects(idxArr, imgWidth, rxStr)
    local lenIdx <const> = #idxArr
    ---@type string[]
    local parts <const> = {}
    local i = 0
    while i < lenIdx do
        i = i + 1
        local idx <const> = idxArr[i]
        parts[i] = string.format(
            "<rect x=\"%d\" y=\"%d\" width=\"1\" height=\"1\" rx=\"%s\"/>",
            idx % imgWidth, idx // imgWidth, rxStr)
    end
    return table.concat(parts, "")
end

-- Image converter

---Converts a flattened Image to all SVG pixel elements (no <svg> wrapper).
---@param img Image flattened active frame
---@param roundPercent integer 0–100
---@param palette Palette active palette (for Indexed mode)
---@return string all <path> or <g><rect…></g> blocks, one per color
local function imgToIconSvgStr(img, roundPercent, palette)
    local strbyte <const> = string.byte

    local imgSpec <const> = img.spec
    local imgWidth <const> = imgSpec.width
    local imgHeight <const> = imgSpec.height
    local colorMode <const> = imgSpec.colorMode
    local imgBytes <const> = img.bytes
    local imgbpp <const> = img.bytesPerPixel
    local imgArea <const> = imgWidth * imgHeight

    -- Step 1: read pixels into pixelDict { ABGR-int → []flatIdx }.
    ---@type table<integer, integer[]>
    local pixelDict <const> = {}

    if colorMode == ColorMode.INDEXED then
        ---@type table<integer, integer>
        local clrIdxToHex <const> = {}
        local alphaIndex <const> = imgSpec.transparentColor
        local i = 0
        while i < imgArea do
            local clrIdx <const> = strbyte(imgBytes, 1 + i)
            if clrIdx ~= alphaIndex then
                local hex = clrIdxToHex[clrIdx]
                if not hex then
                    hex = aseColorToHex(palette:getColor(clrIdx))
                    clrIdxToHex[clrIdx] = hex
                end
                if hex & 0xff000000 ~= 0 then
                    local idcs <const> = pixelDict[hex]
                    if idcs then
                        idcs[#idcs + 1] = i
                    else
                        pixelDict[hex] = { i }
                    end
                end
            end
            i = i + 1
        end
    elseif colorMode == ColorMode.GRAY then
        local i = 0
        while i < imgArea do
            local ibpp <const> = i * imgbpp
            local v <const>, a <const> = strbyte(imgBytes,
                1 + ibpp, imgbpp + ibpp)
            if a > 0 then
                local hex <const> = a << 0x18 | v << 0x10 | v << 0x08 | v
                local idcs <const> = pixelDict[hex]
                if idcs then
                    idcs[#idcs + 1] = i
                else
                    pixelDict[hex] = { i }
                end
            end
            i = i + 1
        end
    elseif colorMode == ColorMode.RGB then
        local i = 0
        while i < imgArea do
            local ibpp <const> = i * imgbpp
            local r <const>, g <const>, b <const>, a <const> = strbyte(
                imgBytes, 1 + ibpp, imgbpp + ibpp)
            if a > 0 then
                local hex <const> = a << 0x18 | b << 0x10 | g << 0x08 | r
                local idcs <const> = pixelDict[hex]
                if idcs then
                    idcs[#idcs + 1] = i
                else
                    pixelDict[hex] = { i }
                end
            end
            i = i + 1
        end
    end

    -- Step 2: build sorted color list (first pixel's visual position → DOM order).
    ---@type integer[]
    local hexArr <const> = {}
    local lenUniques = 0
    for hex, _ in pairs(pixelDict) do
        lenUniques = lenUniques + 1
        hexArr[lenUniques] = hex
    end
    if lenUniques == 0 then return "" end

    table.sort(hexArr, function(a, b)
        return comparator(pixelDict[a][1], pixelDict[b][1], imgWidth)
    end)

    -- Step 3: pre-format rx string (only for roundPercent > 0).
    local rxStr = ""
    if roundPercent > 0 then
        local rx <const> = 0.5 * (roundPercent / 100.0)
        rxStr = string.gsub(string.format("%.2f", rx), "0$", "")
    end

    -- Step 4: emit one SVG element per color.
    ---@type string[]
    local elemsArr <const> = {}
    local h = 0
    while h < lenUniques do
        h = h + 1
        local hex <const> = hexArr[h]
        local idcs <const> = pixelDict[hex]

        -- ABGR → alpha + RRGGBB
        local alpha <const> = (hex >> 0x18) & 0xff
        local webHex <const> = (hex & 0xff) << 0x10
            | (hex & 0xff00)
            | (hex >> 0x10 & 0xff)

        local colorStr <const> = toShortHex(webHex)
        local alphaStr <const> = opacityAttr(alpha)

        local emit
        if roundPercent == 0 then
            local rects <const> = mergeRectsForColor(idcs, imgWidth, imgHeight)
            local pathD <const> = rectsToPathData(rects)
            emit = string.format("<path fill=\"%s\"%s d=\"%s\"/>",
                colorStr, alphaStr, pathD)
        else
            local rectsStr <const> = pixelsToRoundedRects(idcs, imgWidth, rxStr)
            emit = string.format("<g fill=\"%s\"%s>%s</g>",
                colorStr, alphaStr, rectsStr)
        end

        elemsArr[h] = emit
    end

    return table.concat(elemsArr, "\n")
end

-- SVG document builder

---Wraps pixel content in a complete, minimal SVG document.
---@param innerStr string pixel content from imgToIconSvgStr
---@param nativeW integer sprite canvas width
---@param nativeH integer sprite canvas height
---@param title string resolved icon name (XML-escaped inside this function)
---@return string complete SVG file content
local function buildSvgDoc(innerStr, nativeW, nativeH, title)
    return table.concat({
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
        "<svg xmlns=\"http://www.w3.org/2000/svg\"\n",
        "     shape-rendering=\"crispEdges\"\n",
        string.format("     width=\"%d\" height=\"%d\"\n", nativeW, nativeH),
        string.format("     viewBox=\"0 0 %d %d\">\n", nativeW, nativeH),
        string.format("<title>%s</title>\n", xmlEscape(title)),
        innerStr,
        "\n</svg>",
    })
end

-- Dialog

local activeSprite <const> = app.site.sprite
local initHint = ""
if activeSprite then
    local autoName <const> = resolveIconName("", activeSprite)
    initHint = "(auto: " .. autoName .. ")"
end

local dlg <const> = Dialog { title = "SVG Icon Export" }

dlg:entry {
    id       = "iconName",
    label    = "Icon name:",
    text     = defaults.iconName,
    onchange = function()
        local args <const> = dlg.data
        local name <const> = args.iconName
        if name and #name > 0 then
            dlg:modify { id = "iconNameHint", visible = false }
        else
            dlg:modify { id = "iconNameHint", visible = true }
        end
    end,
}

dlg:label {
    id      = "iconNameHint",
    label   = "",
    text    = initHint,
    visible = true,
}

dlg:slider {
    id       = "roundPercent",
    label    = "Corner rounding:",
    min      = 0,
    max      = 100,
    value    = defaults.roundPercent,
    onchange = function()
        local args <const> = dlg.data
        dlg:modify {
            id      = "roundNote",
            visible = args.roundPercent > 0,
        }
    end,
}

dlg:label {
    id      = "roundNote",
    label   = "",
    text    = "Per-pixel rects; no merging in rounded mode",
    visible = defaults.roundPercent > 0,
}

dlg:file {
    id        = "filepath",
    label     = "Save as:",
    save      = true,
    filetypes = { "svg" },
    basepath  = defaultFolder(),
    filename  = "*.svg",
    title     = "Export SVG Icon",
}

dlg:button {
    id      = "confirm",
    text    = "OK",
    focus   = true,
    onclick = function()
        local args <const> = dlg.data

        -- 1. Validate sprite exists.
        local sprite <const> = app.site.sprite
        if not sprite then
            app.alert { title = "Error", text = "No active sprite." }
            return
        end

        -- 2. Validate filepath.
        local filepath <const> = args.filepath
        if not filepath or #filepath == 0 then
            app.alert { title = "Error", text = "Please choose an output file." }
            return
        end
        local ext <const> = string.lower(app.fs.fileExtension(filepath))
        if ext ~= "svg" then
            app.alert { title = "Error", text = "File extension must be .svg" }
            return
        end

        -- 3. Resolve icon name.
        local resolvedName <const> = resolveIconName(args.iconName, sprite)

        -- 4. Get active frame.
        local activeFrObj <const> = app.site.frame
        if not activeFrObj then
            app.alert { title = "Error", text = "No active frame." }
            return
        end

        -- 5. Flatten active frame.
        local activeSpec <const> = sprite.spec
        local flatImg = Image(activeSpec)
        flatImg:drawSprite(sprite, activeFrObj)

        -- 6. Get palette.
        local palette <const> = getPalette(activeFrObj, sprite.palettes)

        -- 7. Build SVG inner content.
        local roundPercent <const> = args.roundPercent or defaults.roundPercent
        local innerStr <const> = imgToIconSvgStr(flatImg, roundPercent, palette)
        if #innerStr == 0 then
            app.alert { title = "Error", text = "No visible pixels found." }
            return
        end

        -- 8. Build full SVG document.
        local nativeW <const> = activeSpec.width
        local nativeH <const> = activeSpec.height
        local svgStr <const> = buildSvgDoc(innerStr, nativeW, nativeH, resolvedName)

        -- 9. Write file.
        local file, err = io.open(filepath, "wb")
        if not file then
            app.alert { title = "Error", text = "Could not open file for writing:\n" .. (err or filepath) }
            return
        end
        file:write(svgStr)
        file:close()

        -- 10. Success.
        app.alert { title = "SVG Icon Export", text = "Icon exported: " .. resolvedName }
        dlg:close()
    end,
}

dlg:button {
    id      = "cancel",
    text    = "Cancel",
    onclick = function()
        dlg:close()
    end,
}

dlg:show { autoscrollbars = true, wait = false }