local lpeg = require "lpeg"
local table = require "table"
local printt = require "printt"
local pathutil = require "pathutil"

local P = lpeg.P
local S = lpeg.S
local R = lpeg.R
local C = lpeg.C
local Ct = lpeg.Ct
local Cg = lpeg.Cg
local Cc = lpeg.Cc
local V = lpeg.V

local function count_lines(_, pos, state)
    if state.pos < pos then
        state.line = state.line + 1
        state.pos = pos
    end
    return pos
end

local exception = lpeg.Cmt(lpeg.Carg(1) , function (_ , pos, parser_state)
	error(string.format("syntax error at [%s] line (%d)", parser_state.file or "", parser_state.line))
	return pos
end)

local eof = P(-1)
local newline = lpeg.Cmt((P"\n"+"\r\n")*lpeg.Carg(1), count_lines)
local line_comment = "//" * (1-newline)^0 * (newline + eof)
local multi_line_comment_end = P"*/"
local multi_line_comment = "/*" * (1-multi_line_comment_end)^0 * multi_line_comment_end * (newline + eof)
local cpp_comment_end = P"]]"
local cpp_comment = "[[" * (1-cpp_comment_end)^0 * cpp_comment_end * (newline + eof)
local blank = S" \t" + newline + line_comment + multi_line_comment + cpp_comment
local blank0 = blank^0
local blanks = blank^1
local semicolon = S";"
local line_end = semicolon + blank0
local alpha = R"az" + R"AZ" + "_" + "." + "\"" + "*" + ":"
local number = R"09"
local alnum = alpha + number
local word = alpha * alnum^0

local name = C(word)
local struct_field = name * blanks * name * blank0 * semicolon * blank0
local enum_field = Ct(name * blank0 * (S"=" * blank0 * C(number^1))^0) * blank0 * P","^0 * blank0
local ami = blank0 * P"ami" * blank0
local amd = blank0 * P"amd" * blank0
local nosession = blank0 * P"nosession" * blank0
local ami_amd = S"[" * blank0 * (S"\"" * C(ami^0 * amd^0 * nosession^0) * S"\"")^0 * blank0 * S","^0 * (blank0 * S"\"" * C(amd^0 * ami^0 * nosession^0) * S"\"")^0 * blank0 * S","^0 * (blank0 * S"\"" * C(amd^0 * ami^0 * nosession^0) * S"\"")^0 * blank0 * S"]"
local param = name * blank0 * name * blank0 * S","^0 * blank0
local throws_exception = name * blank0 * S","^0
local end_tag = P"}" * blank0 * semicolon * blank0

local function multipat(pat)
    return Ct(blank0 * (pat * blanks)^0 * pat^0 * blank0)
end

local function namedpat(name, pat)
    return Ct(Cg(Cc(name), "type") * Cg(pat))
end


local header_word = word + "/"
local header = S"#" * header_word^1 * blank0 * header_word^0 * blank0
local mdl = P"module" * blank0 * name * blank0 * P"{" * blank0
local struct = P"struct" * blank0 * name * blank0 * P"{" * blank0 * multipat(struct_field) * blank0 * end_tag
local class = P"class" * blank0 * name * blank0 * P"{" * blank0 * multipat(struct_field) * blank0 * end_tag
local enum = P"enum" * blank0 * name * blank0 * P"{" * multipat(enum_field) * blank0 * end_tag
local sequence = P"sequence"*blank0*S"<"*blank0*name*blank0*S">"*blank0*name*blank0*semicolon*blank0
local method = namedpat("method", ami_amd^0 * blank0 * name * blank0 * name * blank0 * S"(" * namedpat("params", multipat(param)) * blank0 * S")" * blank0 * (P"throws" * blank0 * namedpat("exception", multipat(throws_exception)))^0 * blank0 * semicolon * blank0)
local extends = P"extends" * blank0 * name * blank0
local interface = P"interface" * blank0 * name * blank0 * extends^0 * P"{" * blank0 * multipat(method * method^0) * blank0 * end_tag
local iinterface = P"interface" * blank0 * name * blank0 * P";" * blank0
local exception = P"exception" * blank0 * name * blank0 * P"{" * blank0 * multipat(struct_field) * blank0 * end_tag

local typedef = P{
    "ALL",
    HEADER = header,
    END = (blank0*P"};"*blank0)^1,
    MODULES = namedpat("module", Ct(mdl^1)),
    STRUCT = namedpat("struct", struct),
    CLASS = namedpat("class", class),
    ENUM = namedpat("enum", enum),
    SEQUENCE = namedpat("sequence", sequence),
    INTERFACE = namedpat("interface", P(interface+iinterface)),
    EXCEPTION = namedpat("exception", exception),
    ALL = multipat(V"HEADER" + V"MODULES" + V"STRUCT" + V"CLASS" + V"ENUM" + V"SEQUENCE" + V"INTERFACE" + V"EXCEPTION" + V"END"),
}
local proto = blank0 * typedef * blank0

local item = {}

function item.struct(sitem)
    local entry = {}
    entry.type = sitem.type
    entry.name = sitem[1]
    entry.fields = {}
    local fieldsitem = sitem[2]
    for i = 1, #fieldsitem, 2 do
        local field = {type=fieldsitem[i], name=fieldsitem[i+1]}
        table.insert(entry.fields, field)
    end

    return entry
end

function item.class(sitem)
    return item.struct(sitem)
end

function item.enum(sitem)
    local entry = {}
    entry.type = sitem.type
    entry.name = sitem[1]
    entry.fields = {}
    local fieldsitem = sitem[2]
    for i = 1, #fieldsitem do
        local field = {name = fieldsitem[i][1], value = fieldsitem[i][2]}
        table.insert(entry.fields, field)
    end
    return entry
end

function item.sequence(sitem)
    local entry = {}
    entry.type = sitem.type
    entry.ref = sitem[1]
    entry.name = sitem[2]
    return entry
end

local function wrap_params(params)
    local param = {}
    for i = 1, #params, 2 do
        local pair = {}
        pair.type = params[i]
        pair.name = params[i+1]
        table.insert(param, pair)
    end
    return param
end

function item.interface(sitem)
    if not sitem[2] then return end -- just a interface, match the role of iinterface 

    local entry = {}
    entry.type = sitem.type
    entry.name = sitem[1]
    entry.methods = {}
    local index = 2
    if type(sitem[2]) == "string" then
        entry.extends = sitem[2]
        index = 3
    end
    local methods = sitem[index]
    for _, method in ipairs(methods) do
        local mtd = {}
        local index = 1
        if method[index] == "ami" or method[index] == "amd" or method[index] == "nosession" then
            if method[index] == "ami" then
                mtd.ami = true
            elseif method[index] == "amd" then
                mtd.amd = true
            elseif method[index] == "nosession" then
                mtd.nosession = true
            end
            index = index + 1
        end
        if method[index] == "ami" or method[index] == "amd" or method[index] == "nosession" then
            if method[index] == "ami" then
                mtd.ami = true
            elseif method[index] == "amd" then
                mtd.amd = true
            elseif method[index] == "nosession" then
                mtd.nosession = true
            end
            index = index + 1
        end
        if method[index] == "ami" or method[index] == "amd" or method[index] == "nosession" then
            if method[index] == "ami" then
                mtd.ami = true
            elseif method[index] == "amd" then
                mtd.amd = true
            elseif method[index] == "nosession" then
                mtd.nosession = true
            end
            index = index + 1
        end
        mtd.rtntype = method[index]
        index = index + 1
        mtd.name = method[index]
        index = index + 1
        mtd.params = wrap_params(method[index][1])
        index = index + 1
        mtd.exception = method[index] and method[index][1] or {}
        table.insert(entry.methods, mtd)
    end
    return entry
end

function item.exception(sitem)
    local entry = {}
    entry.type = sitem.type
    entry.name = sitem[1]
    entry.fields = {}
    for i = 1, #sitem[2], 2 do
        local field = {type = sitem[2][i], name = sitem[2][i+1]}
        table.insert(entry.fields, field)
    end
    return entry
end

local function wrap(r)
    assert(r[1].type == "module")
    local namespace = table.concat(r[1][1], ".")
    local result = {}
    for i = 2, #r, 1 do
        local entry = item[r[i].type](r[i])
        if entry then
            entry.namespace = namespace
            result[entry.name] = entry
        end
    end
    return result
end

local function parser(name, text)
    local state = {file = name, pos = 0, line = 1}
    local r = lpeg.match((proto * -1 + exception), text, 1, state)
    return wrap(r)
end

local function addall(tbl, add)
    for key, value in pairs(add) do
        tbl[key] = value
    end
end

local slice_parser = {}
function slice_parser.parse(pathname)
    print(pathname)
    local files = pathutil.getpathes(pathname)
    local result = {}
    for _, file in ipairs(files) do
        print(file)
        if string.match(file, ".+%.ice") then
            local rfile = io.open(file, "r")
            local content = rfile:read("*a")
            local r = parser(file, content)
            addall(result, r)
        end
    end

    return result
end


return slice_parser
