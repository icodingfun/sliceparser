
local print = print

local function printt(root, key, tab)
	tab = tab or ""
	key = (key and key .. ":") or ""
	print(tab .. key .. "{")
	local innertab = tab .. "  "
	if root ~= nil  then
		for k,v in pairs(root) do
			if type(v) == "table" then
				printt(v, k, tab ..  "  ")
			else
				print(innertab ..tostring(k) .. ":"..tostring(v))
			end
		end
		print(tab .. "}")
	else
		print"nil"
	end
end

return printt
