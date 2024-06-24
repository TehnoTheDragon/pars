--!optimize 2
--!native
--!strict

-- Fast Access
local ssub = string.sub
local slen = string.len

-- Debug
local function __debug_print(obj: any, first_depth: number?)
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
local null: () -> Null
local union: <Types...>(Types...) -> Union<Types...>
local parser: <Out>(fn: ParserFn<Out>) -> Parser<Out>
local string_stream: (string) -> StringStream

-- Types
export type Null = typeof(setmetatable({} :: {
    eq: (Null, any) -> boolean,
}, {} :: {
    __tostring: (Null) -> string,
    __concat: (Null) -> string,
    __eq: (Null, any) -> boolean,
}))
export type Some<T> = {value: T, type: "some"}
export type None = {value: Null, type: "none"}
export type Optional<T> = Some<T> | None
export type Union<Types...> = {
    get: <T>(index: any) -> Optional<T>
}
export type ParserFn<Out> = (input: string, cursor: number) -> (Union<Out>, number)
export type Parser<Out> = typeof(setmetatable({} :: {
    fn: ParserFn<Out>,
    parse: (self: Parser<Out>, input: string) -> (Union<Out>, number),
}, {} :: {

}))
export type StringStream = {
    str: () -> string,
    get: (index: number) -> Optional<string>
}

-- Optional
local function some<T>(value: T): Optional<T>
    return {value = value, type = "some"} :: Optional<T>
end
local function none<T>(): Optional<T>
    return {value = null(), type = "none"} :: Optional<T>
end

-- StringStream
string_stream = function(str: string)
    local strlen = slen(str)
    local string_stream = {}

    function string_stream.str()
        return str
    end

    function string_stream.get(index: number)
        if index < 0 or index > strlen then
            return none()
        end
        return some(ssub(str, index, index))
    end

    return string_stream :: StringStream
end

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

-- Parser
parser = function<Out>(fn: ParserFn<Out>): Parser<Out>
    local parser_meta = {}
    local parser = ({} :: any) :: Parser<Out>
    parser.fn = fn

    function parser:parse(input: string): (Union<Out>, number)
        return self.fn(input, 0)
    end

    return (setmetatable(parser_meta, parser) :: any) :: Parser<Out>
end

-- Parsers

return {
    internal = {
        dbg = __debug_print,
        string_stream = string_stream,
        some = some,
        none = none,
        union = union,
        null = null,
        map = map,
        filter = filter,
    },
    parsers = {

    },
    parser = parser,
}