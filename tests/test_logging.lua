---@diagnostic disable: undefined-global

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function() child.restart({ '-u', 'tests/minimal_init.lua' }) end,
    post_once = child.stop,
  },
})

local eq = MiniTest.expect.equality

-- ring buffer ----------------------------------------------------------------

T['ring buffer'] = MiniTest.new_set()

T['ring buffer']['stores entries in order'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    log.info("first")
    log.info("second")
    log.info("third")
    local entries = log.get_all()
    _G._result = {
      count = #entries,
      msgs = { entries[1].msg, entries[2].msg, entries[3].msg },
    }
  ]])
  local r = child.lua_get('_G._result')
  eq(r.count, 3)
  eq(r.msgs[1], "first")
  eq(r.msgs[2], "second")
  eq(r.msgs[3], "third")
end

T['ring buffer']['returns empty when never written'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    _G._result = #log.get_all()
  ]])
  eq(child.lua_get('_G._result'), 0)
end

T['ring buffer']['clear empties the buffer'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    log.info("one")
    log.info("two")
    log.clear()
    _G._result = #log.get_all()
  ]])
  eq(child.lua_get('_G._result'), 0)
end

T['ring buffer']['wraps at capacity'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    for i = 1, 505 do
      log.info("msg-" .. i)
    end
    local entries = log.get_all()
    _G._result = {
      count = #entries,
      first_msg = entries[1].msg,
      last_msg = entries[#entries].msg,
    }
  ]])
  local r = child.lua_get('_G._result')
  eq(r.count, 500)
  eq(r.first_msg, "msg-6")
  eq(r.last_msg, "msg-505")
end

T['ring buffer']['assigns monotonic sequence numbers'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    log.info("a")
    log.info("b")
    log.info("c")
    local entries = log.get_all()
    _G._result = { entries[1].seq, entries[2].seq, entries[3].seq }
  ]])
  local r = child.lua_get('_G._result')
  eq(r[1], 1)
  eq(r[2], 2)
  eq(r[3], 3)
end

-- log levels -----------------------------------------------------------------

T['log levels'] = MiniTest.new_set()

T['log levels']['info sets INFO level'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    log.info("test")
    _G._result = log.get_all()[1].level
  ]])
  eq(child.lua_get('_G._result'), child.lua_get('vim.log.levels.INFO'))
end

T['log levels']['warn sets WARN level'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    log.warn("test")
    _G._result = log.get_all()[1].level
  ]])
  eq(child.lua_get('_G._result'), child.lua_get('vim.log.levels.WARN'))
end

T['log levels']['error sets ERROR level'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    log.error("test")
    _G._result = log.get_all()[1].level
  ]])
  eq(child.lua_get('_G._result'), child.lua_get('vim.log.levels.ERROR'))
end

T['log levels']['debug sets DEBUG level'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    log.debug("test")
    _G._result = log.get_all()[1].level
  ]])
  eq(child.lua_get('_G._result'), child.lua_get('vim.log.levels.DEBUG'))
end

-- subscribers ----------------------------------------------------------------

T['subscribers'] = MiniTest.new_set()

T['subscribers']['on_change receives new entries'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    _G._received = {}
    log.on_change(function(entry)
      table.insert(_G._received, entry.msg)
    end)
    log.info("hello")
    log.warn("world")
  ]])
  local received = child.lua_get('_G._received')
  eq(#received, 2)
  eq(received[1], "hello")
  eq(received[2], "world")
end

T['subscribers']['off_change removes subscriber'] = function()
  child.lua([[
    local log = require('eigenplug.logging')
    _G._count = 0
    local fn = function() _G._count = _G._count + 1 end
    log.on_change(fn)
    log.info("one")
    log.off_change(fn)
    log.info("two")
  ]])
  eq(child.lua_get('_G._count'), 1)
end

return T
