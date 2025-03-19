---@meta KCD2Test-SeerSuite
local suite = {}

---@alias KCD2Test-SeerSuite*-nil boolean|string|number|integer|function|table|thread|userdata|lightuserdata

suite.browser = {}

---@class KCD2Test-SeerSuite*browser.root
---@field public lua KCD2Test-SeerSuite*lua
---@field public game KCD2Test-SeerSuite*game
---@field public colors KCD2Test-SeerSuite*browser.colors
---@field public helpers table<string,function>
---@field public style KCD2Test-SeerSuite*style?

---@class KCD2Test-SeerSuite*browser.colors
---@field public tree number
---@field public leaf number
---@field public info number
---@field public fake number
---@field public null number

---TODO: get these from other definition files
---@alias KCD2Test-SeerSuite*lua table
---@alias KCD2Test-SeerSuite*game table
---@alias KCD2Test-SeerSuite*style table

---@type KCD2Test-SeerSuite*browser.root
suite.browser.root = {
	lua = ...,
	game = ...,
	colors = {
        tree = 0xFFFF20FF,
        leaf = 0xFFFFFF20,
        info = 0xFF20FFFF,
        fake = 0xEECCCCCC,
        null = 0xFF2020FF
    },
	helpers = {},
}

suite.console = {}

---@class KCD2Test-SeerSuite*console.logger
---@field public log fun(md: KCD2Test-SeerSuite*console.mode, raw: table<integer,string>, ...)
---@field public logger fun(...)?
---@field public color integer
---@field public prefix KCD2Test-SeerSuite*console.log.prefix

---@class KCD2Test-SeerSuite*console.log.prefix
---@field public debug string
---@field public shown string

---@alias KCD2Test-SeerSuite*console.command fun(md: KCD2Test-SeerSuite*console.mode, ...: string)

---@alias KCD2Test-SeerSuite*console.color ...
---@alias KCD2Test-SeerSuite*console.on_enter ...

---@class KCD2Test-SeerSuite*console.definitions
---@field public help fun(...)
---@field public print fun(...)
---@field public tprint fun(...)
---@field public itprint fun(...)
---@field public mprint fun(map: (fun(a: any): b: any), ...)
---@field public imprint fun(map: (fun(a: any): b: any), ...)
---@field public eval fun(...): success: boolean, ...

---@class KCD2Test-SeerSuite*console.mode
---@field public current_text string
---@field public enter_pressed boolean
---@field public history_offset integer
---@field public history table<integer,string>
---@field public shown table<integer,string>
---@field public raw table<integer,string>
---@field public selected table<integer,string>
---@field public selected_last integer?
---@field public colors table<integer,KCD2Test-SeerSuite*console.color>
---@field public index integer
---@field public on_enter KCD2Test-SeerSuite*console.on_enter
---@field public definitions KCD2Test-SeerSuite*console.definitions

---@type KCD2Test-SeerSuite*console.mode
suite.console.mode = ...

---@generic K: KCD2Test-SeerSuite*-nil
---@generic V: any
---@param table table<K,V>
---@param value V
---@param map? fun(value: V): V
---@return K?
function suite.perform_lookup(table,value,map) end

---@generic V: any
---@param array V[]
---@param value V
---@param map? fun(value: V): V
---@return integer?
function suite.perform_index(array,value,map) end

---@generic K: any
---@generic V: KCD2Test-SeerSuite*-nil
---@param table table<K,V>
---@param map? fun(value: V): V
---@return table<V,K>
function suite.build_lookup(table,map) end

---@generic V: KCD2Test-SeerSuite*-nil
---@param array V[]
---@param map? fun(value: V): V
---@return table<V,integer>
function suite.build_index(array,map) end

---@param ... table
function suite.clear(...) end

---@param ... any[]
function suite.iclear(...) end

---@generic K: KCD2Test-SeerSuite*-nil
---@generic V: any
---@param target table<K,V>
---@param ... table<K,V>
---@return table<K,V> target
function suite.merge(target,...) end

---@generic V: any
---@param ... V
---@return fun(): integer?, V? iterator
function suite.vararg(...) end

---@param value any
---@return string type
---@return string? name
function suite.type(value) end

---@param color integer
---@return string hex
function suite.browser.root.helpers.int_to_hex(color) end 

suite.console.log = {
    ---@type KCD2Test-SeerSuite*console.logger
	error = {
        log = ...,
		prefix = {
			debug = "",
			shown = ""
		},
		color = 0xFF2020EE,
	},
    ---@type KCD2Test-SeerSuite*console.logger
	info = {
        log = ...,
		prefix = {
			debug = "",
			shown = ""
		},
		color = 0xFFEEEEEE,
	},
    ---@type KCD2Test-SeerSuite*console.logger
	warning = {
        log = ...,
		prefix = {
			debug = "",
			shown = ""
		},
		color = 0xFF20EEEE,
	},
    ---@type KCD2Test-SeerSuite*console.logger
	history = {
        log = ...,
		prefix = {
			debug = "",
			shown = "] "
		},
		color = 0xEECCCCCC,
	},
    ---@type KCD2Test-SeerSuite*console.logger
	echo = {
        log = ...,
		prefix = {
			debug = "[Echo]:",
			shown = ""
		},
		color = 0xFFEEEEEE,
	},
    ---@type KCD2Test-SeerSuite*console.logger
	print = {
        log = ...,
		prefix = {
			debug = "[Print]:",
			shown = ""
		},
		color = 0xFFEEEEEE,
	},
    ---@type KCD2Test-SeerSuite*console.logger
	returns = {
        log = ...,
		prefix = {
			debug = "[Returns]:",
			shown = ""
		},
		color = 0xFFFFFF20,
	},
    ---@type KCD2Test-SeerSuite*console.logger
	perror = {
        log = ...,
		prefix = {
			debug = "[Error]",
			shown = ""
		},
		color = 0xFF2020EE,
	}
}

suite.console.aliases = {}
suite.console.binds = {}
suite.console.ibinds = {}

---@type table<string,KCD2Test-SeerSuite*console.command>
suite.console.commands = {}

--[[
            Lists the available commands.
]]
---@param md KCD2Test-SeerSuite*console.mode
---@param stub string
suite.console.commands.help = function(md,stub) end

--[[
            Prints a message to the console.
--]]
---@param md KCD2Test-SeerSuite*console.mode
---@param ... string
suite.console.commands.echo = function(md,...) end

--[[
            Executes lua code and shows the result.
--]]
---@param md KCD2Test-SeerSuite*console.mode
---@param ... string
---@return any ...
suite.console.commands.lua = function(md,...) end

--[[
            Executes lua file with args and shows the result.
--]]
---@param md KCD2Test-SeerSuite*console.mode
---@param ... string
---@return any ...
suite.console.commands.luae = function(md,path,...) end

--[[
            Executes a file containing a list of console commands.
--]]
---@param md KCD2Test-SeerSuite*console.mode
---@param path string
suite.console.commands.exec = function(md,path) end

--[[
            Defines a command that represents multiple commands.
--]]
---@param md KCD2Test-SeerSuite*console.mode
---@param name string
---@param ... string
suite.console.commands.alias = function(md,name,...) end

--[[
            Binds a key combination to run commands during gameplay.
--]]
---@param md KCD2Test-SeerSuite*console.mode
---@param ... string
suite.console.commands.bind = function(md,name,...) end

--[[
            Binds a key combination to run commands on the mod gui.
--]]
---@param md KCD2Test-SeerSuite*console.mode
---@param ... string
suite.console.commands.ibind = function(md,name,...) end

---@param text string
function suite.console.rcon(text) end

---@param text string
---@param ... any
---@return ...
function suite.console.rlua(text, ...) end

return suite