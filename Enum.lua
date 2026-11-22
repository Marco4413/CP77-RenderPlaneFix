--[[
Copyright (c) 2025 [Marco4413](https://github.com/Marco4413/CP77-HideGripAndInjection)

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
]]

---@class EnumPrototype
local Enum = {}

---@class EnumMeta
---@field type EnumPrototype
---@field sortedValues integer[]
---@field nextValueFromName record<string, integer>

local function _IsInteger(v)
    return (type(v) == "number") and (v == math.floor(v))
end

---@generic T
---@param definition T
---@return T
function Enum.New(definition)
    ---@type EnumMeta
    local meta = {
        type = Enum,
        sortedValues      = {},
        nextValueFromName = {},
    }

    local enum = setmetatable({}, meta)
    for name, value in next, definition do
        assert(type(name) == "string" and _IsInteger(value), "enum can only contain mappings from string to integer")
        enum[name]  = value
        enum[value] = name
        table.insert(meta.sortedValues, value)
    end

    table.sort(meta.sortedValues)

    for i=1, #meta.sortedValues-1 do
        local name = enum[meta.sortedValues[i]]
        meta.nextValueFromName[name] = meta.sortedValues[i+1]
    end

    return enum
end

function Enum.GetMeta(maybeEnum)
    ---@type EnumMeta|nil
    local meta = getmetatable(maybeEnum)
    return meta and meta.type == Enum and meta or nil
end

function Enum.IsEnum(maybeEnum)
    return Enum.GetMeta(maybeEnum) and true or false
end

---@param enum table
---@return integer|nil
function Enum.MaxValue(enum)
    local meta = Enum.GetMeta(enum)
    return meta.sortedValues[#meta.sortedValues]
end

---@alias EnumNextFn fun(enum: table, name: string|nil): string|nil, integer|nil

---@type EnumNextFn
function Enum.Next(enum, name)
    local value
    repeat
        name, value = next(enum, name)
    until name == nil or (type(name) == "string" and type(value) == "number")
    return name, value
end

---@type EnumNextFn
function Enum.SortedNext(enum, name)
    local meta = Enum.GetMeta(enum)

    local value
    if name ~= nil then
        value = meta.nextValueFromName[name]
        name  = enum[value]
        return name, value
    end

    if #meta.sortedValues <= 0 then return; end
    value = meta.sortedValues[1]
    name  = enum[value]
    return name, value
end

---@generic T
---@param enum T
---@return EnumNextFn
---@return T
function Enum.Iterator(enum)
    return Enum.Next, enum
end

---@generic T
---@param enum T
---@return EnumNextFn
---@return T
function Enum.SortedIterator(enum)
    return Enum.SortedNext, enum
end

---@param name string
---@return string
function Enum.ToHumanCase(name)
    local humanCase = name:gsub("(.)([A-Z])", "%1 %2")
    return humanCase
end

---@param name string
---@return string
function Enum.ToSnakeCase(name)
    local snakeCase = name:gsub("(.)([A-Z])", "%1_%2")
    return snakeCase:lower()
end

---@param enum table
---@param currentValue integer
---@param label string|nil
---@return integer
function Enum.ImCombo(enum, currentValue, label)
    local currentName = enum[currentValue]

    local maxTextWidth = 0
    for name, _ in Enum.Iterator(enum) do
        local width = ImGui.CalcTextSize(Enum.ToHumanCase(name))
        if width > maxTextWidth then
            maxTextWidth = width
        end
    end

    local width = maxTextWidth + 40 -- magic number representing the drop-down button

    ImGui.SetNextItemWidth(width)
    local selectedValue = currentValue
    if ImGui.BeginCombo(label or "", Enum.ToHumanCase(currentName)) then
        for name, value in Enum.SortedIterator(enum) do
            if ImGui.Selectable(Enum.ToHumanCase(name)) then
                selectedValue = value
            end
        end
        ImGui.EndCombo()
    end

    return selectedValue
end

return Enum
