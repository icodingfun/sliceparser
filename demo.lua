local parser = require "sliceparser"
local printt = require "printt"

collectgarbage "stop"

local r = parser.parse("F:/workspace/sliceparser")

printt(r)