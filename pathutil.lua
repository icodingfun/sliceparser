local lfs = require "lfs"
local upath = {}
function upath.getpathes(rootpath, pathes)
    pathes = pathes or {}

    ret, files, iter = pcall(lfs.dir, rootpath)
    if ret == false then
        return pathes
    end
    for entry in files, iter do
        local next = false
        if entry ~= '.' and entry ~= '..' then
            local path = rootpath .. '/' .. entry
            local attr = lfs.attributes(path)
            if attr == nil then
                next = true
            end

            if next == false then
                if attr.mode == 'directory' then
                    upath.getpathes(path, pathes)
                else
                    table.insert(pathes, path)
                end
            end
        end
        next = false
    end
    return pathes
end

return upath