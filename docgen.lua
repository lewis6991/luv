local doctypes = require("docs")
local doc = doctypes[1]
local types = doctypes[2]

--- @param str string
--- @return string
local function dedent(str)
  local prefix = 99

  str = str:gsub('^\n', ''):gsub('%s+$', '')

  for line in str:gmatch("[^\n]+") do
    local s, e = line:find("^%s*")
    local amount = (e - s) + 1
    if amount < prefix then
      prefix = amount
    end
  end

  local result = {} --- @type string[]
  for line in str:gmatch("([^\n]*)\n?") do
    result[#result + 1] = line:sub(prefix + 1)
  end

  local ret = table.concat(result, '\n')
  ret = ret:gsub('\n+$', '')

  return ret
end

--- @param lvl integer
--- @param str string
local function heading(lvl, str)
  return string.rep("#", lvl).." " .. str:gsub(' %- ', ' — ')
end

local function isoptional(ty)
  if type(ty) == 'string' then
    return ty:sub(-4, -1) == '|nil'
  end
  return ty.optional
end

--- @param method Doc.Method
local function sig(method)
  local ret = {} --- @type string[]
  ret[#ret + 1] = '`uv.'
  ret[#ret + 1] = method.name
  ret[#ret + 1] = "("
  for _, param in ipairs(method.params or {}) do
    local optional = isoptional(param.type)
    if optional then
      ret[#ret + 1] = "["
    end
    ret[#ret + 1] = param.name
    if optional then
      ret[#ret + 1] = "]"
    end
    if param ~= method.params[#method.params] then
      ret[#ret + 1] = ", "
    end
  end
  ret[#ret + 1] = ")`"
  return table.concat(ret, '')
end

local function pad(lvl)
  return string.rep(' ', lvl * 2)
end

local normty

--- @param ty Doc.Type.Fun
--- @param lvl? integer
--- @param desc? string
local function normtyfun(ty, lvl, desc)
  local r = {} --- @type string[]
  r[#r + 1] = '`callable`'
  if ty.optional then
    r[#r] = r[#r] .. ' or `nil`'
  end
  if desc then
    r[#r] = r[#r] .. ' '..desc
  end
  for i, arg in pairs(ty) do
    if type(i) == 'number' and i > 1 then
      if arg[1] == 'err' and arg[2] == 'string|nil' then
        arg[2] = 'nil|string'
      end
      r[#r + 1] = ('%s- `%s`: %s'):format(pad(lvl), arg[1], normty(arg[2], lvl + 1))
      if arg[3] then
        r[#r] = r[#r] .. ' ' .. arg[3]
      end
    end
  end

  return table.concat(r, '\n')
end

--- @param ty Doc.Type.Table
--- @param lvl? integer
--- @param desc? string
local function normtytbl(ty, lvl, desc)
  local r = {} --- @type string[]
  r[#r + 1] = '`table`'
  if ty.optional then
    r[#r] = r[#r] .. ' or `nil`'
  end
  if desc then
    r[#r] = r[#r] .. ' '..desc
  end
  for i, arg in pairs(ty) do
    if type(i) == 'number' and i > 1 then
      --- @type string, Doc.Type, string?, string?
      local name, aty, default, adesc = arg[1], arg[2], arg[3], arg[4]
      r[#r + 1] = ('%s- `%s`: %s'):format(pad(lvl), name, normty(aty, lvl+1))
      if default then
        r[#r] = ("%s (default: `%s`)"):format(r[#r], default)
      end
      if adesc then
        r[#r] = r[#r] .. ' ' .. adesc
      end
    end
  end

  return table.concat(r, '\n')
end

--- @param ty string
--- @param lvl? integer
--- @param desc? string
local function normtystrtbl(ty, lvl, desc)
  local optional = false
  if ty:sub(-4, -1) == '|nil' then
    optional = true
    ty = ty:sub(1, -5)
  end

  if ty:sub(-2, -1) == '[]' then
    return 'array of '..normty(ty:sub(1, -3), lvl, desc)
  end

  local r = {
    '`table`'
    .. (optional and ' or `nil`' or '')
    .. (desc and ' '..desc or '')
  }

  for var, t in ty:gmatch("([a-z0-9_]+)%s*:%s*([a-z_]+),?%s*") do
    r[#r + 1] = ('%s- `%s`: %s'):format(pad(lvl), var, normty(t, lvl + 1))
  end
  return table.concat(r, '\n')
end

--- @param ty string
--- @param lvl? integer
--- @param desc? string
local function normtystr(ty, lvl, desc)

  do -- look in types table
    local ty1, optional = ty, false
    if ty1:sub(-4, -1) == '|nil' then
      optional = true
      ty1 = ty1:sub(1, -5)
    end

    if types[ty1] then
      local ty2 = types[ty1]
      ty2.optional = optional
      return normty(ty2, lvl, desc)
    end
  end

  do -- TODO(lewis6991): remove
    if ty == 'uv_handle_t' or ty == 'uv_req_t' or ty == 'uv_stream_t' then
      return '`userdata` for sub-type of `' .. ty .. '`'
    end
    ty = ty:gsub('uv_[a-z_]+', '%0 userdata')
    ty = ty:gsub('%|', '` or `')
  end

  local desc_str = desc and ' '..desc or ''
  return '`'..ty..'`' .. desc_str
end

--- @param ty string|Doc.Type.Fun|Doc.Type.Table
--- @param lvl? integer
--- @param desc? string
function normty(ty, lvl, desc)
  lvl = lvl or 0
  local f
  if type(ty) == 'string' then
    if ty:sub(1, 1) == '{' then
      f = normtystrtbl
    else
      f = normtystr
    end
  elseif ty[1] == 'function' then
    f = normtyfun
  elseif ty[1] == 'table' then
    f = normtytbl
  end
  return f(ty, lvl, desc)
end

--- @param out file*
--- @param param Doc.Method.Param
local function write_param(out, param)
  out:write(string.format("- `%s`:" , param.name))
  local ty = param.type
  if ty then
    out:write(" ", normty(ty, 1, param.desc))
  elseif param.desc then
    out:write(' ', param.desc)
  end
  if param.default then
    out:write(string.format(" (default: `%s`)", param.default))
  end
  out:write("\n")
end

--- @param out file*
--- @param x string|Doc.Method.Return[]
--- @param variant? string
local function write_return(out, x, variant)
  local variant_str = variant and (" (%s version)"):format(variant) or ''
  if type(x) == 'string' then
    out:write(("**Returns%s:** %s\n"):format(variant_str, normty(x)))
  elseif type(x) == 'table' then
    if x[2] and x[2][2] == 'err' and x[3] and x[3][2] == 'err_name' then
      local sty = x[1][1]
      if type(sty) == 'string' then
        sty = sty:gsub('%|nil$', '')
      else
        sty.optional = false
      end
      local rty = normty(sty, nil, 'or `fail`')
      out:write(("**Returns%s:** %s\n\n"):format(variant_str, rty))
      return
    else
      local tys = {} --- @type string[]
      for _, ret in ipairs(x) do
        tys[#tys + 1] = normty(ret[1])
      end
      out:write(("**Returns%s:** %s\n"):format(variant_str, table.concat(tys, ', ')))
    end
  else
    out:write("**Returns:** Nothing.\n")
  end
  out:write("\n")
end

--- @param out file*
--- @param method Doc.Method
--- @param lvl integer
local function write_method(out, method, lvl)
  out:write(heading(lvl, sig(method)))
  out:write("\n\n")

  if method.method_form then
    out:write(('> method form `%s`\n\n'):format(method.method_form))
  end

  if method.params then
    out:write("**Parameters:**\n")
    for _, param in ipairs(method.params) do
      write_param(out, param)
    end
    out:write("\n")
  end

  if method.desc then
    out:write(dedent(method.desc))
    out:write("\n\n")
  end

  if method.returns_doc then
      out:write("**Returns:**")
      local r = dedent(method.returns_doc)
      if r:sub(1, 1) == '-' then
        out:write("\n")
      else
        out:write(" ")
      end
      out:write(r)
      out:write("\n")
      out:write("\n")
  elseif method.returns_sync and method.returns_async then
    write_return(out, method.returns_sync, "sync")
    write_return(out, method.returns_async, "async")
  else
    write_return(out, method.returns)
  end


  if method.example then
    out:write(dedent(method.example))
    out:write("\n\n")
  end

  if method.see then
    out:write(("See [%s][].\n\n"):format(method.see))
  end

  for _, note in ipairs(method.notes or {}) do
    local notes = dedent(note)
      out:write("**Note**:")
    if notes:sub(1,3) == '1. ' then
      out:write('\n', notes, '\n\n')
    else
      out:write(' ', notes, '\n\n')
    end
  end

  for _, warn in ipairs(method.warnings or {}) do
    out:write(string.format("**Warning**: %s\n\n", dedent(warn)))
  end

  if method.since then
    out:write(('**Note**: New in libuv version %s.\n\n'):format(method.since))
  end
end

--- @param out file*
--- @param section Doc
--- @param lvl integer
local function write_section(out ,section, lvl)
  local title = section.title
  if title then
    out:write(heading(lvl, title))
    out:write("\n\n")
  end
  local id = section.id
  if id then
    local tag = assert(title):match('^`[a-z_]+`') or title
    out:write(string.format('[%s]: #%s\n\n', tag, id))
  end
  if section.desc then
    out:write(dedent(section.desc))
    out:write("\n\n")
  end

  for _, method in ipairs(section.methods or {}) do
    write_method(out, method, lvl + 1)
  end

  for _, subsection in ipairs(section.sections or {}) do
    write_section(out, subsection, lvl + 1)
  end
end

local out = assert(io.open("docs.md", "w"))

for _, section in ipairs(doc) do
  write_section(out, section, 1)
end
