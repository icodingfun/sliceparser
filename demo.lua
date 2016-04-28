local parser = require "sliceparser"
local printt = require "printt"

local filePath = "F:\\workspace\\work\\XSanGoGreen\\XSanGoGreen.Game.Protocol\\icegenerated\\com\\XSanGoG\\eci\\Protocol\\"

collectgarbage "stop"

local xsginterface = "XsgInterface"

local function saveFile(name, content)
    local file, err = io.open(filePath .. name .. ".java", "w+")
    if not file then
        print("ERROR: " .. err)
    end
    file:write(content)
    file:close()
end

local emptyInterface = [[
package com.XSanGoG.eci.Protocol;

public interface XsgInterface {

}
]]

local function saveEmptyInterface()
    saveFile(xsginterface, emptyInterface)
end

local classTemplate = [[
package $package;

$import

public class $classname implements java.io.Serializable {
    private static final long serialVersionUID = 1L;

    $fields

    public $classname() {

    }

    public $classname($fieldsargs) {
        $fieldsinit
    }
}
]]

local enumTemplate = [[
package $package;

public enum $classname {
    $fields
}
]]

local interfaceTemplate = [[
package $package;

import com.XSanGoG.eci.Protocol.XsgInterface;
import com.morefun.XSanGoG.gate.common.Async;
import com.morefun.XSanGoG.gate.common.NoSession;
import com.morefun.XSanGoG.gate.common.Xsg;
import com.morefun.XSanGoG.gate.backend.ResponseDispatch;
$import

@Xsg
public interface $classname extends $extends {
    $methods
}
]]

local syncSessionMethodTemplate = [[
$rtn $methodName (String sessionId$args)$exceptions;
]]

local asnycSessionMethodTemplate = [[
@Async void $methodName (String sessionId, ResponseDispatch response$args)$exceptions;
]]

local syncNoSessionMethodTemplate = [[
@NoSession $rtn $methodName ($args)$exceptions;
]]

local asnycNoSessionMethodTemplate = [[
@NoSession @Async void $methodName (ResponseDispatch response$args)$exceptions;
]]


local buildInType = {
    string = "String",
    bool = "boolean",
}

local java = {}

function java.struct(all, entry)
    local importsTbl = {}
    local fieldsTbl = {}
    local fieldsInitTbl = {}
    local fieldArgsTbl = {}
    
    local fields = entry.fields
    for _, field in ipairs(fields) do
        local type = field.type
        if buildInType[type] then
            type = buildInType[type]
        else
            local refType = all[type]
            if refType then
                local importName = refType.name;
                if refType.type == "sequence" then
                    type = refType.ref .. "[]"
                    importName = refType.ref
                end
                local import = string.format("import %s.%s;\n", refType.namespace, importName)
                table.insert(importsTbl, import)
            end
        end
        local fieldItem = string.format("public %s %s;", type, field.name)
        local initItem = string.format("this.%s = %s;", field.name, field.name)
        local fieldArgItem = string.format("%s %s", type, field.name)
        table.insert(fieldsTbl, fieldItem)
        table.insert(fieldsInitTbl, initItem)
        table.insert(fieldArgsTbl, fieldArgItem)
    end

    local replTable = {
        package = entry.namespace,
        import = table.concat(importsTbl, "\n"),
        classname = entry.name,
        fieldsargs = table.concat(fieldArgsTbl, ", "),
        fields = table.concat(fieldsTbl, "\n    "),
        fieldsinit = table.concat(fieldsInitTbl, "\n        ")
    }
 
    local content = string.gsub(classTemplate, "%$(%w+)", replTable)

    saveFile(entry.name, content)
end

function java.class(all, entry)
    java.struct(all, entry)
end

local function getMethodArgsDeclare(all, importsTbl, args)
    local argsTbl = {}
    for _, arg in ipairs(args) do
        local tp = arg.type
        if buildInType[tp] then
            tp = buildInType[tp]
        else
            local refType = all[tp]
            if refType then
                local importName = refType.name;
                if refType.type == "sequence" then
                    tp = refType.ref .. "[]"
                    importName = refType.ref
                end
                table.insert(importsTbl, import)
            end
        end
        local name = arg.name
        if (string.match(arg.name, "%*")) then
            name = string.sub(name, 2)
            tp = tp .. "Prx"
        end
        if (string.match(tp, "%*")) then 
            tp = string.sub(tp, 1, -2)
            tp = tp .. "Prx"
        end
        local argDeclare = string.format("%s %s", tp, name)
        table.insert(argsTbl, argDeclare)
    end
    return argsTbl
end

local function getMethodExceptionDeclare(all, importsTbl, exceptions)
    local exceptionsTbl = {}
    for _, exception in ipairs(exceptions) do
        table.insert(exceptionsTbl, exception)
    end
    return exceptionsTbl
end

local function getMethodDeclare(all, importsTbl, method)
    local rtntype = method.rtntype
    if buildInType[rtntype] then
        rtntype = buildInType[rtntype]
    else
        local refType = all[rtntype]
        if refType then
            local importName = refType.name;
            if refType.type == "sequence" then
                rtntype = refType.ref .. "[]"
                importName = refType.ref
            end
            table.insert(importsTbl, import)
        end
    end
    local argsTbl = getMethodArgsDeclare(all, importsTbl, method.params)
    local exceptionsTbl = getMethodExceptionDeclare(all, importsTbl, method.exception)
    local exceptionDec = ""
    if exceptionsTbl and #exceptionsTbl > 0 then
        exceptionDec = "throws " .. table.concat(exceptionsTbl, ", ")
    end
    
    local argsDec = table.concat(argsTbl, ", ")
    
    local methodTemplate
    if method.nosession then
        if method.amd then
            if #argsDec > 0 then
                argsDec = ", " .. argsDec
            end
            methodTemplate = asnycNoSessionMethodTemplate
        else
            methodTemplate = syncNoSessionMethodTemplate
        end
    else
        if method.amd then
            if #argsDec > 0 then
                argsDec = ", " .. argsDec
            end
            methodTemplate = asnycSessionMethodTemplate
        else
            if #argsDec > 0 then
                argsDec = ", " .. argsDec
            end
            methodTemplate = syncSessionMethodTemplate
        end
    end
    
    local replTable = {
        rtn = rtntype,
        methodName = method.name,
        args = argsDec,
        exceptions = exceptionDec
    }
    
    local content = string.gsub(methodTemplate, "%$(%w+)", replTable)

    return content
end

function java.interface(all, entry)
    local importsTbl = {}
    local methodsTbl = {}
    local entendsTbl = {}
    
    local extends = xsginterface
    
    if entry.extends then
        extends = entry.extends
    end

    local methods = entry.methods
    for _, method in ipairs(methods) do
        table.insert(methodsTbl, getMethodDeclare(all, importsTbl, method))
    end
    
    local replTable = {
        package = entry.namespace,
        classname = entry.name,
        import = table.concat(importsTbl, "\n"),
        methods = table.concat(methodsTbl, "\n    "),
        extends = extends
    }
    
    local content = string.gsub(interfaceTemplate, "%$(%w+)", replTable)
    
    saveFile(entry.name, content)
end

function java.enum(all, entry)
    local fieldsTbl = {}

    local fields = entry.fields
    for _, field in ipairs(fields) do
        local fieldItem = string.format("%s,", field.name)
        table.insert(fieldsTbl, fieldItem)
    end

    local replTable = {
        package = entry.namespace,
        classname = entry.name,
        fields = table.concat(fieldsTbl, "\n    ")
    }

    local content = string.gsub(enumTemplate, "%$(%w+)", replTable)

    saveFile(entry.name, content)
end

function java.exception(all, entry)
    java.struct(all, entry)
end

function java.sequence(all, entry)
    -- do nothing
end

local function genJava(functable)
    for name, entry in pairs(functable) do
        java[entry.type](functable, entry)
    end
end

local r = parser.parse("F:\\workspace\\work\\XSanGoGreen\\XSanGoGreen.Game.Protocol\\slice")

saveEmptyInterface()
genJava(r)
printt(r)