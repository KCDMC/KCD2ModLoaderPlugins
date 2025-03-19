---@meta LuaENVY-ENVY
local envy = {}

---@alias LuaENVY-ENVY*file userdata|table|string|fun(...): table

--[[ 
          Definition of `getfenv` in lua 5.2 for convenience
--]]
---@param fn integer | function? chunk function or stack level
---@return table? env environment the chunk uses
function envy.getfenv( fn ) end
---@alias LuaENVY-ENVY.getfenv ...

--[[ 
          Definition of `setfenv` in lua 5.2 for convenience
--]]
---@param fn integer | function? chunk function or stack level
---@param env table? environment to set the chunk to use
function envy.setfenv( fn, env ) end
---@alias LuaENVY-ENVY.setfenv ...


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
---@see LuaENVY-ENVY.import_all to shallow copy into an environment
---@see LuaENVY-ENVY.import_as_fallback to use the result as a fallback
---@param binder function|integer? function to export locals
---@return table result table bound to the upvalues <br/>
function envy.export( binder ) end
---@alias LuaENVY-ENVY.export ...


--[[
          Loads a lua file/module relative to a plugin.
    <br/> Alternatively, takes an absolute path,
    <br/>   or a file handle, or a chunk function.
    <br/> Also, if given a table, it will just return that.

    Usage:
        local helper = import(_ENV,"helper.lua")
--]]
---@see LuaENVY-ENVY.export to share locals from the file
---@see LuaENVY-ENVY.import_all like python's `import *`
---@see LuaENVY-ENVY.import_as_fallback `import_all`, without shallow copy
---@param env table environment (typically a plugin)
---@param file LuaENVY-ENVY*file path relative to plugin, absolute path, file handle, chunk function, or module table
---@param fenv table? environment to give the function (not relevant if a module table was given)
---@param level integer? stack level to send errors to
---@param ... any arguments passed in to the chunk function (if relevant)
---@return table data return value from the file/module
---@return any ... additional return values from the file/module <br/>
function envy.import(env,file,fenv,level,...) end
---@alias LuaENVY-ENVY.import ...

--[[
          Uses `import` to get the data from a lua file/module,
    <br/>   then imports all those fields into the given environment.
    <br/> **Note**: These fields will never update, as they are shallow copied.

    Usage:
        import_all(_ENV,"util.lua")
--]]
---@see LuaENVY-ENVY.import how it obtains the data from the file/module
---@see LuaENVY-ENVY.import_as_fallback this, but without shallow copying.
---@see LuaENVY-ENVY.import_as_shared*auto this, but writes fallback as well.
---@param env table environment (typically a plugin)
---@param file LuaENVY-ENVY*file path relative to plugin, absolute path, file handle, chunk function, or module table
---@param fenv table? environment to give the function (not relevant if a module table was given)
---@param level integer? stack level to send errors to <br/>
function envy.import_all(env,file,fenv,level,...) end
---@alias LuaENVY-ENVY.import_all ...

--[[
          Uses `import` to get the data from a lua file/module,
    <br/>   then imports all those fields into the given environment,
    <br/>   but rather than copying them, it sets them as a fallback.
    <br/> **Note**: If you assign to these fields, they will no longer update.

    Usage:
        import_all_fallback(_ENV,"shell.lua")
--]]
---@see LuaENVY-ENVY.import how it obtains the data from the file/module
---@see LuaENVY-ENVY.import_all this, but by shallow copying.
---@param env table environment (typically a plugin)
---@param file LuaENVY-ENVY*file path relative to plugin, absolute path, file handle, chunk function, or module table
---@param fenv table? environment to give the function (not relevant if a module table was given)
---@param level integer? stack level to send errors to <br/>
function envy.import_as_fallback(env,file,fenv,level,...) end
---@alias LuaENVY-ENVY.import_as_fallback ...

--[[
          Uses `import` to get *and set* the data from a lua file/module,
    <br/>   then imports all those fields into the given environment,
    <br/>   but rather than copying them, it sets them as a fallback.
    <br/> **Note**: If you assign to these fields, they will update the original too!

    Usage:
        import_as_shared(_ENV,"state.lua")
--]]
---@see LuaENVY-ENVY.import how it obtains the data from the file/module
---@see LuaENVY-ENVY.import_all this, but by shallow copying.
---@see LuaENVY-ENVY.import_as_shared this, but writes don't fallback.
---@param env table environment (typically a plugin)
---@param file LuaENVY-ENVY*file path relative to plugin, absolute path, file handle, chunk function, or module table
---@param fenv table? environment to give the function (not relevant if a module table was given)
---@param level integer? stack level to send errors to <br/>
function envy.import_as_shared(env,file,fenv,level,...) end
---@alias LuaENVY-ENVY.import_as_shared ...

--[[
          The extras are: 
    <br/> `import`, `import_all`, `import_as_fallback`, `import_as_shared`, to extend the environment.
    <br/> `public` to define fields accessible to others
    <br/> `private` to define fields only accessible to itself
    <br/> `export`, to expose locals to other files

    Usage:
        local _ENV, ext = setup(_ENV)
        import_all(_ENV,ext)
--]]
---@class LuaENVY-ENVY*extras: table
---@field public import fun(file: LuaENVY-ENVY*file, fenv: table?,...): table loads a lua file/module relative to *your* plugin.
---@field public import_all fun(file: LuaENVY-ENVY*file, fenv: table?,...) uses `import` to get the data from a lua file/module (shallow copied into *your* environment).
---@field public import_as_shared fun(file: LuaENVY-ENVY*file, fenv: table?,...) uses `import` to get the data from a lua file/module (as fallback to *your* environment).
---@field public import_as_fallback fun(file: LuaENVY-ENVY*file, fenv: table?,...) uses `import` to get the data from a lua file/module (as a fallback with linked writes from *your* environment).
---@field public export fun(binder: function|integer?): result: table exports locals by using a function bound to them as upvalues.
---@field public private table the new 'private' environment
---@field public public table the original 'public' environment
---@field public globals table the base globals that all plugins share
---@field public getfenv function WIP: definition pending...
---@field public setfenv function WIP: definition pending...
---@field public table tablelib WIP: definition pending...
---@field public next function WIP: definition pending...
---@field public rawnext function WIP: definition pending...
---@field public inext function WIP: definition pending...
---@field public rawinext function WIP: definition pending...
---@field public rawtostring function WIP: definition pending...
---@field public rawpairs function WIP: definition pending...
---@field public rawipairs function WIP: definition pending...
---@field public qrawpairs function WIP: definition pending...
---@field public qrawipairs function WIP: definition pending...

--[[
          Creates a new environment from a given environment, 
    and also returns `extras` bound to the new environemnt.

    Usage:
        _ENV = setup(_ENV)
    *   -   -   -   -   -   -   -   -
        local _ENV, ext = setup(_ENV)
        import_all(_ENV,ext)
--]]
---@see LuaENVY-ENVY*extras
---@see LuaENVY-ENVY.auto
---@see LuaENVY-ENVY.import_all
---@return table newenv
---@return LuaENVY-ENVY*extras extras
function envy.setup(env) end
---@alias LuaENVY-ENVY.setup ...

--[[
          Finds the caller (at the stack `level`) to `setup` its environment and `import` all `extras`.
    
    Usage:
        ---@module 'LuaENVY-ENVY-auto'
        auto()
--]]
---@see LuaENVY-ENVY*extras
---@see LuaENVY-ENVY.setup
---@see LuaENVY-ENVY.import
---@param level integer?
---@return LuaENVY-ENVY*extras extras
function envy.auto(level) end
---@alias LuaENVY-ENVY.auto ...

envy.globals = _G

return envy