--!optimize 2
--!native
--!strict

-- Debug
local function __debug_print(obj: any, first_depth)
    local result = ""
    local function __debug_print_table(t, depth)
        local indent = string.rep(" ", depth)
        for k, v in pairs(t) do
            if typeof(v) == "table" then
                result ..= `{indent}{k}: \{\n`
                __debug_print_table(v, depth + 2)
                result ..= `{indent}\}\n`
            else
                result ..= `{indent}{k}: {v}\n`
            end
        end
    end
    
    __debug_print_table(obj, first_depth or 0)
    print(result)
end

-- Declarations
local null
local union

-- Types
export type Null = typeof(setmetatable({} :: {
    eq: (Null, any) -> boolean,
}, {} :: {
    __tostring: (Null) -> string,
    __concat: (Null) -> string,
    __eq: (Null, any) -> boolean,
}))
export type Some<T> = T
export type None = Null
export type Optional<T> = Some<T> | None
export type Union<Types...> = {
    get: <T>(index: any) -> Optional<T>
}

-- Union Object
union = function<Types...>(...: Types...): Union<Types...>
    local _union = table.pack(...)
    local union: Union<Types...> = {} :: Union<Types...>
    function union:get<T>(index: any): Optional<T>
        local value = _union[index] :: any
        return if value == nil then null() else value
    end
    return union
end

-- Null Object
null = function(): Null
    return setmetatable({
        eq = function(self, y)
            if typeof(y) ~= "table" then
                return y == nil
            end
            return getmetatable(self :: any).__name == getmetatable(y).__name
        end
    }, {
        __tostring = function(self) return "null" end,
        __concat = function(self) return "" end,
        __eq = function(self, y) return y == self end,
        __name = "null"
    }) :: Null
end

-- Funtional
local function map<InputType, KeyType, OutputType>(x: {InputType}, fn: (value: InputType, key: KeyType) -> OutputType): {OutputType}
    local y: {OutputType} = {}
    for key, value in pairs(x) do
        y[key] = fn(value, key :: any)
    end
    return y
end

local function filter<InputType, KeyType>(x: {InputType}, fn: (value: InputType, key: KeyType) -> InputType): {InputType}
    local y: {InputType} = {}
    for key, value in pairs(x) do
        y[key] = fn(value, key :: any)
    end
    return y
end

return {
    internal = {
        dbg = __debug_print,
        union = union,
        null = null,
        map = map,
        filter = filter,
    }
}