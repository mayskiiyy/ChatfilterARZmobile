script_name("Chat Filter")
script_author("Mayskiy")
script_version("1.0")

require "moonloader"
local imgui = require "mimgui"
local ffi = require "ffi"
local encoding = require "encoding"
encoding.default = "CP1251"
local u8 = encoding.UTF8
local sampev = require 'lib.samp.events'

local new, str, sizeof = imgui.new, ffi.string, ffi.sizeof

local MAX_LINES = 2000 -- Настройки длины чат лога
local history = {}
local filters_global = {}
local filters_visual = {}
local filters_history = {}
local folders = {}

local CFG_PATH = getWorkingDirectory() .. "/config/simple_cf.cfg"

local win_filter = new.bool(false)
local win_history = new.bool(false)

local buf_add = new.char[256]()
local buf_folder_name = new.char[64]()
local buf_folder_tags = new.char[256]()
local buf_search = new.char[256]()

function save()
    local f = io.open(CFG_PATH, "w")
    if f then
        local function write_list(name, list)
            f:write("["..name.."]\n")
            for _, v in ipairs(list) do f:write(v .. "\n") end
        end
        write_list("GLOBAL", filters_global)
        write_list("VISUAL", filters_visual)
        write_list("HISTORY", filters_history)
        f:write("[FOLDERS]\n")
        for _, folder in ipairs(folders) do 
            f:write(folder.name .. "|" .. folder.tags_raw .. "\n") 
        end
        f:close()
    end
end

function load()
    local f = io.open(CFG_PATH, "r")
    if f then
        local mode = ""
        for line in f:lines() do
            if line:find("^%[.*%]$") then mode = line:match("%[(.*)%]")
            elseif line ~= "" then
                if mode == "GLOBAL" then table.insert(filters_global, line)
                elseif mode == "VISUAL" then table.insert(filters_visual, line)
                elseif mode == "HISTORY" then table.insert(filters_history, line)
                elseif mode == "FOLDERS" then
                    local name, tags_raw = line:match("(.*)|(.*)")
                    if name and tags_raw then 
                        table.insert(folders, {name = name, tags_raw = tags_raw}) 
                    end
                end
            end
        end
        f:close()
    end
end

function matches_pattern(text, pattern_list)
    local clean_text = text:gsub("{%x%x%x%x%x%x}", "")
    for _, pattern in ipairs(pattern_list) do
        if pattern ~= "" then
            local lua_pattern = pattern:gsub("[%-%+%.%?%(%)%[%]%^%$%%]", "%%%1"):gsub("%*", ".*")
            if clean_text:find("^" .. lua_pattern .. "$") then return true end
        end
    end
    return false
end

function matches_multi_tags(text, tags_raw)
    local tags = {}
    for tag in tags_raw:gmatch("%S+") do table.insert(tags, tag) end
    return matches_pattern(text, tags)
end

function add_to_log(text, color)
    if matches_pattern(text, filters_history) then return end
    
    local r, g, b, a = bit.band(bit.rshift(color, 24), 0xFF)/255, bit.band(bit.rshift(color, 16), 0xFF)/255, bit.band(bit.rshift(color, 8), 0xFF)/255, bit.band(color, 0xFF)/255
    if a == 0 then a = 1 end
    
    table.insert(history, {
        msg = text:gsub("{%x%x%x%x%x%x}", ""), 
        clr = imgui.ImVec4(r, g, b, a),
        time = os.date("%H:%M:%S")
    })
    if #history > MAX_LINES then table.remove(history, 1) end
end

function process_message(color, text)
    if matches_pattern(text, filters_global) then return false end
    if matches_pattern(text, filters_visual) then
        add_to_log(text, color)
        return false 
    end
    add_to_log(text, color)
    return true
end

function sampev.onServerMessage(color, text) return process_message(color, text) end
function sampev.onChatMessage(playerId, text) 
    local name = sampGetPlayerNickname(playerId)
    return process_message(0xFFFFFFFF, name .. "[" .. playerId .. "]: " .. text) 
end

imgui.OnFrame(function() return win_filter[0] or win_history[0] end, function()
    imgui.GetStyle().ScrollbarSize = 25.0

    if win_filter[0] then
        imgui.Begin("Filter Config", win_filter)
        if imgui.BeginTabBar("F_Tabs") then
            local function draw_f(label, list, tag)
                if imgui.BeginTabItem(label) then
                    imgui.InputText("Pattern##"..tag, buf_add, 256)
                    if imgui.Button("Add to "..label, imgui.ImVec2(-1, 0)) then
                        local t = u8:decode(str(buf_add))
                        if t ~= "" then table.insert(list, t) save() ffi.fill(buf_add, 256, 0) end
                    end
                    imgui.BeginChild("sc"..tag, imgui.ImVec2(0, 200), true)
                    for i, v in ipairs(list) do
                        imgui.TextWrapped(u8(v))
                        imgui.SameLine(imgui.GetWindowWidth() - 50)
                        if imgui.Button("X##"..tag..i) then table.remove(list, i) save() end
                    end
                    imgui.EndChild()
                    imgui.EndTabItem()
                end
            end
            draw_f("Global (All)", filters_global, "g")
            draw_f("Visual (Only /ch)", filters_visual, "v")
            draw_f("History Hide", filters_history, "h")
            
            if imgui.BeginTabItem("Folders") then
                imgui.InputText("Name", buf_folder_name, 64)
                imgui.InputText("Tags (ex: *VIP* *PREM* or *[D]*)", buf_folder_tags, 256)
                if imgui.Button("Create Folder", imgui.ImVec2(-1, 0)) then
                    local n, t = u8:decode(str(buf_folder_name)), u8:decode(str(buf_folder_tags))
                    if n ~= "" and t ~= "" then table.insert(folders, {name = n, tags_raw = t}) save() end
                end
                imgui.Separator()
                for i, f in ipairs(folders) do
                    imgui.Text(u8(f.name .. " [" .. f.tags_raw .. "]"))
                    imgui.SameLine(imgui.GetWindowWidth() - 50)
                    if imgui.Button("X##f"..i) then table.remove(folders, i) save() end
                end
                imgui.EndTabItem()
            end
            imgui.EndTabBar()
        end
        imgui.End()
    end

    if win_history[0] then
        imgui.SetNextWindowSize(imgui.ImVec2(750, 500), imgui.Cond.FirstUseEver)
        imgui.Begin("Chat History", win_history)
        imgui.InputText("Search", buf_search, 256)
        local s_query = u8:decode(str(buf_search)):lower()
        
        if imgui.BeginTabBar("H_Tabs") then
            local function draw_list(tags_string)
                imgui.BeginChild("ch_list".. (tags_string or "all"), imgui.ImVec2(0, 0), true)
                for i, e in ipairs(history) do
                    local visible = true
                    if tags_string and not matches_multi_tags(e.msg, tags_string) then visible = false end
                    if s_query ~= "" and not e.msg:lower():find(s_query, 1, true) then visible = false end
                    
                    if visible then
                        imgui.TextDisabled("["..e.time.."]")
                        imgui.SameLine()
                        imgui.PushStyleColor(imgui.Col.Text, e.clr)
                        if imgui.Selectable(u8(e.msg) .. "##" .. i .. (tags_string or "")) then
                            setClipboardText(u8(e.msg))
                            sampAddChatMessage("{00BFFF}[Filter]{FFFFFF} Copied!", -1)
                        end
                        imgui.PopStyleColor()
                    end
                end
                if imgui.GetScrollY() >= imgui.GetScrollMaxY() then imgui.SetScrollHereY(1.0) end
                imgui.EndChild()
            end

            if imgui.BeginTabItem("All") then draw_list(nil) imgui.EndTabItem() end
            for _, f in ipairs(folders) do
                if imgui.BeginTabItem(u8(f.name)) then draw_list(f.tags_raw) imgui.EndTabItem() end
            end
            imgui.EndTabBar()
        end
        imgui.End()
    end
end)

function main()
    while not isSampLoaded() do wait(500) end
    if not doesDirectoryExist(getWorkingDirectory() .. "/config") then createDirectory(getWorkingDirectory() .. "/config") end
    load()
    sampRegisterChatCommand("cf", function() win_filter[0] = not win_filter[0] end)
    sampRegisterChatCommand("ch", function() win_history[0] = not win_history[0] end)
    sampAddChatMessage("{00BFFF}[Filter]{FFFFFF} v1.0 loaded. Tags separated by space.", -1)
    wait(-1)
end

