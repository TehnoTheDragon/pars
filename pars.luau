--!optimize 2
--!native
--!strict

-- Fast Access
local ssub = string.sub
local slen = string.len
local sfind = string.find

-- Debug
local function dbg(obj: any, first_depth: number?)
    if obj == nil then
        print("nil")
        return
    elseif typeof(obj) == "string" then
        print(obj)
        return
    end

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
local create_parser: <Out>(fn: ParserFn<Out>) -> Parser<Out>
local string_stream: (string) -> StringStream
local range: (min: number, max: number?) -> Range
local unimplemented: () -> ()
local ok: <T>(value: T) -> Ok<T>
local err: <T>(err: T) -> Err<T>
local some: <T>(value: T) -> Optional<T>
local none: <T>() -> Optional<T>

-- Types
export type Range = {min: number, max: number}
export type Ok<T> = {value: T, type: "ok"}
export type Err<T> = {err: T, type: "err"}
export type Result<T, E> = Ok<T> | Err<E>
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
    data: {any},
    get: <T>(index: any) -> Optional<T>,
    unpack: () -> ...any
}
export type ParserFnOutput<Out> = Union<Out, number>
export type ParserFn<Out> = (input: StringStream, cursor: number) -> Result<ParserFnOutput<Out>, any>
export type Parser<Out> = typeof(setmetatable({} :: {
    fn: ParserFn<Out>,
    parse: (self: Parser<Out>, input: string) -> Result<ParserFnOutput<Out>, any>,

    optional: (Parser<Out>) -> Parser<Out>,
    discard: (Parser<Out>) -> Parser<Out>,
    range: (Parser<Out>, range: Range) -> Parser<Out>,
    label: (Parser<Out>, label: string) -> Parser<Out>,
}, {} :: {

}))
export type StringStream = {
    str: () -> string,
    len: () -> number,
    get: (index: number) -> Optional<string>,
}

-- Result
ok = function<T>(value: T): Ok<T>
    return { value = value, type = "ok" }
end
err = function<E>(err: E): Err<E>
    return { err = err, type = "err" }
end

-- Unimplemented
unimplemented = function()
    error(`Unimplemented`, 3)
end

-- Range
range = function(min: number, max: number?): Range
    if max then
        assert(max > min, `Max({max}) value must be larger than Min({min}) value`)
    end
    return { min = min, max = max or math.huge } :: Range
end

-- Optional
some = function<T>(value: T): Optional<T>
    return {value = value, type = "some"} :: Optional<T>
end
none = function<T>(): Optional<T>
    return {value = null(), type = "none"} :: Optional<T>
end

-- StringStream
string_stream = function(str: string): StringStream
    local strlen = slen(str)
    local string_stream = {}

    function string_stream.str()
        return str
    end

    function string_stream.len()
        return strlen
    end

    function string_stream.get(index: number)
        if index <= 0 or index > strlen then
            return none()
        end
        return some(ssub(str, index, index))
    end

    return string_stream
end

-- Union Object
union = function<Types...>(...: any): Union<Types...>
    local _union = {...}
    local union: Union<Types...> = {data = _union} :: Union<Types...>
    function union.get<T>(index: any): Optional<T>
        local value = _union[index] :: any
        return if value == nil then none() else some(value)
    end
    function union.unpack()
        return unpack(_union)
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
create_parser = function<Out>(fn: ParserFn<Out>): Parser<Out>
    local parser_meta = {}
    local parser = ({} :: any) :: Parser<Out>
    parser.fn = fn

    function parser:parse(input: string): Result<ParserFnOutput<Out>, any>
        return self.fn(string_stream(input), 1)
    end

    function parser:optional()
        return create_parser(function(input: StringStream, cursor: number)
            local result = self.fn(input, cursor)
            if result.type == "err" then
                return ok(union(null(), cursor))
            end
            return result
        end)
    end

    function parser:discard()
        return create_parser(function(input: StringStream, cursor: number)
            local result = self.fn(input, cursor)
            if result.type == "err" then
                return result
            end
            return ok(union(null(), result.value.get(2).value))
        end)
    end

    function parser:range(range: Range)
        return create_parser(function(input: StringStream, cursor: number)
            local buf = ""
            local pos = cursor
            while true do
                if pos > range.max then
                    break
                end

                local result = self.fn(input, pos)
                if result.type == "ok" then
                    buf ..= result.value.get(1).value :: string
                    pos = result.value.get(2).value :: number
                else
                    break
                end
            end

            if slen(buf) < range.min then
                return err(`Expected at least {range.min} got {slen(buf)}`)
            end

            return ok(union(buf, pos))
        end)
    end

    function parser:label(label: string)
        unimplemented()
    end

    return (setmetatable((parser :: any) :: {}, parser_meta) :: any) :: Parser<Out>
end

-- QoL
local function check_char(input: StringStream, cursor: number): Result<Null, string>
    if input.get(cursor) == nil then
        return err("Invalid State")
    elseif cursor > input.len() then
        return err("End of Input")
    end
    return ok(null())
end

-- Parsers
local function char<Out>(charset: string): Parser<Out>
    return create_parser(function(input: StringStream, cursor: number)
        local check = check_char(input, cursor)
        if check.type == "err" then
            return check
        end

        local char = input.get(cursor).value :: string
        if not sfind(charset, char) then
            return err(`Expected one of the chars "{charset}", found '{char}'`)
        end
        
        return ok(union(char, cursor + 1))
    end)
end

local function empty<Out>(): Parser<Out>
    return create_parser(function(input: StringStream, cursor: number)
        return ok(union(null(), cursor))
    end)
end

local function eol<Out>(): Parser<Out>
    return create_parser(function(input: StringStream, cursor: number)
        local check = check_char(input, cursor)
        if check.type == "ok" then
            return err(`Expected end of input, found {input.get(cursor).value}`)
        end
        return ok(union(null(), cursor))
    end)
end

local function any<Out>(): Parser<Out>
    return create_parser(function(input: StringStream, cursor: number)
        local check = check_char(input, cursor)
        if check.type == "err" then
            return check
        end

        local char = input.get(cursor).value :: string
        return ok(union(char, cursor + 1))
    end)
end

local function lit<Out>(literal: string): Parser<Out>
    local literal_length = slen(literal)
    return create_parser(function(input: StringStream, cursor: number)
        local index = 0
        while true do
            local pos = cursor + index
            if index == literal_length then
                return ok(union(literal, pos))
            end

            local check = check_char(input, pos)
            if check.type == "err" then
                return check
            end

            local char = input.get(pos).value :: string
            if ssub(literal, pos, pos) ~= char then
                return err(`Literal: {literal}, expected '{ssub(literal, pos, pos)}' but got '{char}'`)
            end
            index += 1
        end
    end)
end

local function is_a<Out>(predicate: (string) -> boolean): Parser<Out>
    return create_parser(function(input: StringStream, cursor: number)
        local check = check_char(input, cursor)
        if check.type == "err" then
            return check
        end

        local char = input.get(cursor).value :: string
        if not predicate(char) then
            return err(`'{char}' is not valid`)
        end

        return ok(union(char, cursor + 1))
    end)
end

return {
    internal = {
        dbg = dbg,
        string_stream = string_stream,
        unimplemented = unimplemented,
        ok = ok,
        err = err,
        some = some,
        none = none,
        union = union,
        null = null,
        map = map,
        filter = filter,
    },
    parsers = {
        empty = empty,
        eol = eol,
        char = char,
        any = any,
        lit = lit,
        is_a = is_a,
    },
    range = range,
    parser = create_parser,
}