---@meta LuaENVY-ENVY-auto

--[[
          Loads a lua file/module relative to *your* plugin.
    <br/> Alternatively, takes an absolute path,
    <br/>   or a file handle, or a chunk function.
    <br/> Also, if given a table, it will just return that.

    Usage:
        local helper = import("helper.lua")
--]]
---@see LuaENVY-ENVY-auto.export to share locals from the file
---@see LuaENVY-ENVY-auto.import_all like python's `import *`
---@see LuaENVY-ENVY-auto.import_as_fallback `import_all`, without shallow copy
---@param file LuaENVY-ENVY*file path relative to plugin, absolute path, file handle, chunk function, or module table
---@param fenv table? environment to give the function (not relevant if a module table was given)
---@param ... any arguments passed in to the chunk function (if relevant)
---@return table data return value from the file/module
---@return any ... additional return values from the file/module <br/>
function import(file,fenv,...) end
---@alias LuaENVY-ENVY-auto.import ...

--[[
          Uses `import` to get the data from a lua file/module,
    <br/>   then imports all those fields into *your* environment.
    <br/> **Note**: These fields will never update, as they are shallow copied.

    Usage:
        import_all("util.lua")
--]]
---@see LuaENVY-ENVY-auto.import how it obtains the data from the file/module
---@see LuaENVY-ENVY-auto.import_as_fallback this, but without shallow copying.
---@param file LuaENVY-ENVY*file path relative to plugin, absolute path, file handle, chunk function, or module table
---@param fenv table? environment to give the function (not relevant if a module table was given)
---@param ... any arguments passed in to the chunk function (if relevant) <br/>
function import_all(file,fenv,...) end
---@alias LuaENVY-ENVY-auto.import_all ...

--[[
          Uses `import` to get the data from a lua file/module,
    <br/>   then imports all those fields into *your* environment,
    <br/>   but rather than copying them, it sets them as a fallback.
    <br/> **Note**: If you assign to these fields, they will no longer update.

    Usage:
        import_all_fallback("shell.lua")
--]]
---@see LuaENVY-ENVY-auto.import how it obtains the data from the file/module
---@see LuaENVY-ENVY-auto.import_all this, but by shallow copying.
---@see LuaENVY-ENVY-auto.import_as_shared this, but writes fallback as well.
---@param file LuaENVY-ENVY*file path relative to plugin, absolute path, file handle, chunk function, or module table
---@param fenv table? environment to give the function (not relevant if a module table was given)
---@param ... any arguments passed in to the chunk function (if relevant) <br/>
function import_as_fallback(file,fenv,...) end
---@alias LuaENVY-ENVY-auto.import_as_fallback ...

--[[
          Uses `import` to get *and set* the data from a lua file/module,
    <br/>   then imports all those fields into *your* environment,
    <br/>   but rather than copying them, it sets them as a fallback.
    <br/> **Note**: If you assign to these fields, they will update the original too!

    Usage:
        import_as_shared("state.lua")
--]]
---@see LuaENVY-ENVY-auto.import how it obtains the data from the file/module
---@see LuaENVY-ENVY-auto.import_all this, but by shallow copying.
---@see LuaENVY-ENVY-auto.import_as_shared this, but writes don't fallback.
---@param file LuaENVY-ENVY*file path relative to plugin, absolute path, file handle, chunk function, or module table
---@param fenv table? environment to give the function (not relevant if a module table was given)
---@param ... any arguments passed in to the chunk function (if relevant) <br/>
function import_as_shared(file,fenv,...) end
---@alias LuaENVY-ENVY-auto.import_as_shared*auto ...

--[[
          Exports locals by using a function bound to them as upvalues.
    <br/> When the result is written to, it will write to the original locals.
    <br/> Multiple values may be bound at once.

    Usage:
        local value = 1; print(value) -- 1
        local function binder() return binder, value end
        local result = export(binder)
        result.value = 2; print(value) -- 2
        print(result.binder == binder) -- true
--]]
---@see LuaENVY-ENVY-auto.import_all to shallow copy into an environment
---@see LuaENVY-ENVY-auto.import_as_fallback to use the result as a fallback
---@param binder function|integer? function to export locals
---@return table result table bound to the upvalues <br/>
function export( binder ) end
---@alias LuaENVY-ENVY-auto.export ...

-- the original 'public' environment
public = _ENV

-- the new 'private' environment
private = setmetatable({},{__index=public})

-- WIP: definition pending...
---@type function
getfenv = ...

-- WIP: definition pending...
---@type function
setfenv = ...

-- WIP: definition pending...
---@type tablelib
table = ...

-- WIP: definition pending...
---@type function
next = ...

-- WIP: definition pending...
---@type function
rawnext = ...

-- WIP: definition pending...
---@type function
inext = ...

-- WIP: definition pending...
---@type function
rawinext = ...

-- WIP: definition pending...
---@type function
rawtostring = ...

-- WIP: definition pending...
---@type function
rawpairs = ...

-- WIP: definition pending...
---@type function
rawipairs = ...

-- WIP: definition pending...
---@type function
qrawpairs = ...

-- WIP: definition pending...
---@type function
qrawipairs = ...