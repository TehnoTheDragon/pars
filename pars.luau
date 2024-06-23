-- Fast Access
local sub = string.sub
local find = string.find
local length = string.len

-- Types
export type MapFn<O, U> = (O) -> U
export type ConvertFn<O, U> = (O) -> U
export type ParserFn<I, O> = (input: {I}, start: cursor) -> (O, cursor)
export type Parser<I, O> = {
    fn: ParserFn<I, O>,
    parse: (Parser<I, O>, input: I) -> O,

    discard: (Parser<I, O>) -> Parser<I, O>,
    optional: (Parser<I, O>) -> Parser<I, O>,
    rep: (Parser<I, O>, min_: number, max_: number?) -> Parser<I, O>,

    map: (Parser<I, O>) -> Parser<I, O>,
    convert: (Parser<I, O>) -> Parser<I, O>,
}
export type char = string
export type cursor = number
export type CharStream = {

}

-- NullObject
local function NULL()
    return setmetatable({t="null"}, {
        __tostring = function()
            return "null"
        end,
        __concat = function()
            return ""
        end,
        __eq = function(y)
            return y == nil
        end
    })
end
local function IS_NULL(x)
    return typeof(x) == "table" and x.t == "null"
end

-- Functional
local function map<T, V>(t: {T}, fn: (T) -> V): {V}
    local mapped: {V} = {}
    for k,v in pairs(t) do
        mapped[k] = fn(v)
    end
    return mapped
end

-- Wrappers
function _create_stream_of_chars(input: string): CharStream
    local len = length(input)
    local char_stream = {}

    function char_stream.get(index)
        if index > len or index < 1 then
            return nil
        end
        return sub(input, index, index)
    end

    function char_stream.str()
        return input
    end

    return (char_stream :: any) :: CharStream
end

-- Methods
function _create_parser<I, O>(fn: ParserFn<I, O>): Parser<I, O>
    local parser_meta = {}
    function parser_meta:__index(key)
        return rawget(self, key)
    end
    function parser_meta:__add(another_parser)
        return _create_parser(function(input, start)
            local left, left_pos = self.fn(input, start)
            if left then
                local right, right_pos = another_parser.fn(input, left_pos)
                return {left, right}, right_pos
            end
            error("Invalid")
        end)
    end
    function parser_meta:__sub(another_parser)
        return _create_parser(function(input, start)
            local left, left_pos = self.fn(input, start)
            if left then
                local _, right_pos = another_parser.fn(input, left_pos)
                return {left}, right_pos
            end
            error("Invalid")
        end)
    end
    function parser_meta:__mul(another_parser)
        return _create_parser(function(input, start)
            local left, left_pos = self.fn(input, start)
            if left then
                local right, right_pos = another_parser.fn(input, left_pos)
                return {right}, right_pos
            end
            error("Invalid")
        end)
    end
    function parser_meta:__div(another_parser)
        return _create_parser(function(input, start)
            local success, left, left_pos = pcall(function() return self.fn(input, start) end)
            if success then
                return {left}, left_pos 
            end
            local success, right, right_pos = pcall(function() return another_parser.fn(input, start) end)
            if success then
                return {right}, right_pos 
            end
            error("Invalid")
        end)
    end
    -- function parser_meta:__pow(another_parser)
    --     local combined_parser = _create_parser()
    --     return combined_parser
    -- end
    local parser = {}
    parser.fn = fn

    function parser:parse(input)
        local output, _ = self.fn(_create_stream_of_chars(input), 1)
        return output or NULL(), NULL()
    end

    function parser:parse_at(input, at: cursor)
        return self.fn(_create_stream_of_chars(input), at)
    end

    function parser:discard()
        return _create_parser(function(input, start)
            local _, end_ = self.fn(input, start)
            return NULL(), end_ or NULL()
        end)
    end

    function parser:optional()
        return _create_parser(function(input, start)
            local success, result = pcall(function()
                return self.fn(input, start)
            end)
            if success then
                return result, start
            else
                return start
            end
        end)
    end

    function parser:rep(min_, max__)
        local max_ = max__ or math.huge
        return _create_parser(function(input, start)
            local buf = ""
            local pos = start
            while true do
                if pos > max_ then
                    break
                end

                local success, result, new_pos = pcall(function()
                    return self.fn(input, pos)
                end)
                if success then
                    buf ..= result
                    pos = new_pos
                else
                    break
                end
            end

            assert(length(buf) >= min_, `Expected at least {min_} but got {length(buf)}`)

            return buf, pos
        end)
    end

    function parser:map<O, U>(mapFn: MapFn<O, U>)
        return _create_parser(function(input, start)
            local result, new_pos = self.fn(input, start)
            return map(result, mapFn), new_pos
        end)
    end

    function parser:convert<O, U>(convertFn: ConvertFn<O, U>)
        return _create_parser(function(input, start)
            local result, new_pos = self.fn(input, start)
            return {convertFn(result)}, new_pos
        end)
    end

    return (setmetatable(parser, parser_meta) :: any) :: Parser<I, O>
end

function empty<I>(): Parser<I, nil>
    return _create_parser(function(input, start)
        return start
    end)
end

function one_of<I>(symbols): Parser<I, I>
    return _create_parser(function(input, start)
        local c = input.get(start)
        assert(c ~= nil, "Incomplete")
        assert(find(symbols, c) ~= nil, `Expected one of '{symbols}' but got '{c}'`)
        return c, start + 1
    end)
end

function any<I>(): Parser<I, I>
    return _create_parser(function(input, start)
        local c = input.get(start)
        assert(c ~= nil, "reached the end of input")
        return c, start + 1
    end)
end

function sym<I>(symbol: char): Parser<I, I>
    return _create_parser(function(input, start)
        local c = input.get(start)
        assert(c ~= nil, "reached the end of input")
        assert(symbol == c, `Expected '{symbol}' but got '{c}'`)
        return c, start + 1
    end)
end

function seq<I>(sequence: string): Parser<I, I>
    return _create_parser(function(input, start)
        local sequence_length = length(sequence)
        local index = 0
        while true do
            local pos = start + index
            if index == sequence_length then
                return sequence, pos
            end
            local c = input.get(pos)
            assert(sub(sequence, pos, pos) == c, `Sequence: {sequence}, expected {sub(sequence, pos, pos)} but got {c}`)
            index += 1
        end
    end)
end

function is_a<I>(predication: (I) -> boolean): Parser<I, I>
    return _create_parser(function(input, start)
        local buf = ""
        local pos = start
        while true do
            local c = input.get(pos)
            if c and predication(c) then
                buf ..= c
                pos += 1
            else
                break
            end
        end
        return buf, pos
    end)
end

return {
    parser = _create_parser,
    empty = empty,
    one_of = one_of,
    any = any,
    sym = sym,
    seq = seq,
    is_a = is_a,
}