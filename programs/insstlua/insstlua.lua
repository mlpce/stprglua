global require

local <const> k_RCache = require("gembindl.utility.rcache")
local <const> k_Launcher = k_RCache.require("gembindl.utility.launcher")

return k_Launcher:launch("JINIT.LUA", "INSSTLUA.RSC", "INSSTLUA.H")
