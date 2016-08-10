io.output():setvbuf("no")

--package.path = package.path..";D:/DavidDownloads/ZeroBraneStudio/lualibs/metalua/?.lua"

require('metalua')

local startDir = ''

local requirePrefix = 'require::'
local function loadFileSrc(name)
  local f = io.open(name, 'r')
  if not f then error("File:"..tostring(name).." not found") end
  local src = f:read('*a')
  f:close()
  return src
 end
 
local function astFromFile(filename)
  local src = loadFileSrc(filename)
  return mlc.ast_of_luastring(src,'@'..filename)
end

local function location(ast)
  local i = ast.lineinfo and ast.lineinfo.first
  if not i then return "-" end
  return string.format("%d:%d %s",i[1],i[2], i[4])
end

local function getLastComment(ast)
  local comment 
  if ast.lineinfo and ast.lineinfo.last and ast.lineinfo.last.comments then
    for _,v in ipairs(ast.lineinfo.last.comments) do
      comment = (comment or '')..v[1].."\n"
    end
  end
  return comment
end

local function getFirstComment(ast)
  local comment 
  if ast.lineinfo and ast.lineinfo.first and ast.lineinfo.first.comments then
    for _,v in ipairs(ast.lineinfo.first.comments) do
      comment = (comment or '')..v[1].."\n"
    end
  end
  return comment
end

local function zbsClass(ast, scope) 
  return  {
    location = location(ast),
    type = 'class',
    childs = {},
    inherits = ""
  }
end

local function zbsConvertToClass(zbsother) 
  zbsother.type = 'class'
  zbsother.childs = {}
  zbsother.inherits = ""
end

local function zbsFunction(ast, valuetype, scope)
  return {
     type = 'function',
     location = location(ast),
     valuetype = valuetype
  }
end

local function zbsMethod(ast, valuetype, scope)
  return {
     type = 'method',
     location = location(ast),
     valuetype = valuetype
  }
end


local function zbsValue(ast, valuetype, scope)
  return {
     type = 'value',
     location = location(ast),
     valuetype = valuetype
  }
end


local function zbsUnresolvedIdentValue(ast, ident, scope)
  return {
      type = 'unresolvedIdentValue',
      location = location(ast),
      ident = ident,
      unresolved =  true,
  }
end

local function zbsComplexTableAccess(ast, scope)
  return {
      type = 'complexTableAccess',
      location = location(ast),
      unresolved = true
  }
end

local function zbsUnresolvedFunctionResult(ast, func, scope)
  return {
     type = 'unresolvedFunctionResult',
     func = func,
     location = location(ast),
     unresolved = true,
  }
end

local function zbsUnresolvedFunctionArgument(ast, idx, func, scope)
  local uri = {
     type = 'unresolvedFunctionArgument',
     location = location(ast),
     valuetype = nil,
     func = func,
     idx = idx,
     unresolved = true,
  }
  
  uri.valuetype = zbsUnresolvedIdentValue(ast, uri, scope)
  return uri
end



local function zbsUnresolvedIdent(ast, name, scope)
  local uri = {
     type = 'unresolvedIdent',
     location = location(ast),
     valuetype = nil,
     name = name,
     unresolved = true,
  }
  
  uri.valuetype = zbsUnresolvedIdentValue(ast, uri, scope)
  return uri
end


local function updateValue(o, n)
  if o == n then return end 
  
  if o == nil or n == nil then
    print("oops")
  end
      
  --everyone has refs to o, so we have to do value based update
  --scalars first
  o.description = n.description
  o.comment = n.comment
  o.location = n.location
  o.name = n.name
  o.type = n.type
  o.unresolved = n.unresolved
  o.metatable = n.metatable
  
  o.ident = n.ident
  o.func = n.func
  --replace any out of date children
  if n.childs then
      if not o.childs then o.childs = {} end
      if o.childs ~= n.childs then
        local oc = o.childs
        for k,v in pairs(n.childs) do
           if oc[k] then
             if oc[k] ~= v then
               updateValue(oc[k], v)
             end
           else
             oc[k] = v
           end
        end
      end
  else
    o.childs = nil
  end
  
  if n.valuetype then
     if o.valuetype == nil then
       o.valuetype = n.valuetype
     elseif o.valuetype ~= n.valuetype then
       updateValue(o.valuetype, n.valuetype) --cross fingers and hope for no infinite loop here
     end
  else
    o.valuetype = nil
  end
end



local function createGlobalScope()
  local newscope = {
        ['::type'] = "Global",
    }
  newscope['::parent'] = newscope
  newscope['::global'] = newscope
  newscope['_G'] =  {
    --description = "Fake _G",
    type = 'class',
    childs = {},
    inherits = "",
  } 
  
  setmetatable(newscope['_G'].childs,{__index = newscope})
  return newscope
end


local function cleanGlobalScope(scope)
  scope['::type'] = nil
  scope['::parent'] = nil
  scope['::global'] = nil
  scope['_G'] = ni
  
  local replaced = {}
  local toremove = {}
  for k,v in pairs(scope) do
    if k:match(requirePrefix) then
      local oldk = k
      k = k:gsub(requirePrefix, "")
      replaced[k] = v
      table.insert(toremove, oldk)
    end
  end
  for k,v in pairs(replaced) do
    scope[k] = v
  end
  
  for _,k in ipairs(toremove) do
     scope[k] = nil
  end
  
  
end

local function pushScope(scope, scopetype)
  local newscope = {
        ['::type'] = scopetype,
        ['::parent'] = scope
    }
  setmetatable(newscope, { __index = scope })
  return newscope
end

local function popScope(scope)
   return scope['::parent']
end

local function isTable(v)
  return type(v) == "table"
end

local function findScopeForName(scope, name)
  local s = scope
  while s['::parent'] ~= s do
    if s[name] then break end
    s = popScope(s)
  end
  return s
end

local function setInScope(scope, name, value)
  local s = findScopeForName(scope, name)
  if s[name] then
    --only replace unresolved instances
    if s[name].unresolved then
      updateValue(s[name], value)
    end
  else
    s[name] = value
  end
  
end



local function bestReturn(currentBest,ret)
  local bestRet = currentBest
  
  if ret == nil then return currentBest end
   
  local retPrec = { ['boolean'] = 1,['number'] = 2 ,['string'] = 3 }
  if ret and ret.valuetype and bestRet and bestRet.valuetype then
    local prec = retPrec[ret.valuetype]
    local bestprec = retPrec[bestRet.valuetype]
    if prec == nil and bestprec ~= nil then
      bestRet = ret
    elseif prec ~= nil and bestprec ~= nil and prec > bestprec then
      bestRet = ret
    end
  else
    if bestRet == nil then bestRet = ret end
    if bestRet ~= nil then 
      if bestRet.unresolved and not ret.unresolved then
        return ret
      end
    end
  end
  return bestRet
end

local function resolveValuetype(ast,valuetype,scope)
  if type(valuetype) == "function" then
    valuetype = valuetype()
  end
  
  if isTable(valuetype) then return valuetype end
  if valuetype == "string" or valuetype == "number" or valuetype == "boolean" then
    return zbsValue(ast,valuetype,scope)
  end
  local val = scope[valuetype]
  if val then
    return val
  else
    return zbsUnresolvedIdent(ast, valuetype, scope)
  end
end

local processBlock
local processFunc
local processTable
local processIdent
local processIndex
local processCall
local processIf
local processFornum
local processForin
local processInvoke
local processOp
local processFile

--must return zbs repr or nil
local function processExpr(ast, scope)
  --print ("resolving expression")
  if not ast then
    print("oops")
  end
  
  local tag = ast.tag
  local switch = {
    ['Nil'] = function() return nil end,
    ['Dots'] = function() return nil end, --todo maybe we can do this by tracking special var
    ['True'] = function() return zbsValue(ast, "boolean", scope) end,
    ['False'] =  function() return zbsValue(ast, "boolean", scope) end,
    ['Number'] = function() return zbsValue(ast, "number", scope) end,
    ['String'] = function() return zbsValue(ast, "string", scope) end,
    ['Function'] = function() return processFunc(ast, scope) end,
    ['Table'] = function() return processTable(ast, scope) end,
    ['Id'] = function() return processIdent(ast, scope) end,
    ['Index'] = function() return processIndex(ast, scope) end,
    ['Call'] = function() return processCall(ast, scope) end,
    ['Invoke'] = function() return processInvoke(ast, scope) end,
    ['Paren'] = function() return processExpr(ast[1], scope) end,
    ['Op'] = function() return processOp(ast, scope) end 
  }
   local action = switch[tag]
  local res = nil
  if action then res = action() end
--  updateLastComment(ast)
  return res

end

function processFunc(ast, scope)
  local args = ast[1]
  local body = ast[2]
  --create func scope
  local func
  
  local valuetype = function(...)
    
    local newscope = pushScope(scope, "Function")
    local fargs = { ... }
    newscope['::dots'] = fargs
    for i,arg in ipairs(args) do
      if arg.tag == 'Id' then
        local scopeval = fargs[i] or zbsUnresolvedFunctionArgument(ast, i, func, scope)
        newscope[arg[1]] = scopeval
      end
    end  
    
    return processBlock(body, newscope)
  end
 
  if args[1] and args[1].tag == 'Id' and args[1][1] == 'self' then
    func = zbsMethod(ast, valuetype, scope)
  else
    func = zbsFunction(ast, valuetype,scope)
  end
  
  return func
end

local function resolveFunctionValueType(funcdef, args, ast,scope)
    if funcdef == nil then
      print("oops")
    end
    
    local valtype = funcdef.valuetype
     -- no value maybe we are a call tpye detect __call
    if not valtype and isTable(funcdef) and funcdef.metatable and funcdef.metatable.childs 
      and funcdef.metatable.childs.__call then
       valtype = funcdef.metatable.childs.__call.valuetype
    end
    
    if type(valtype) == "function" then
      valtype = valtype(args)
    end
    
    if not valtype then
      return zbsUnresolvedFunctionResult(ast, funcdef, scope)
    end
    
    return resolveValuetype(ast,valtype,scope)
end


function processCall(ast, scope)
  local func = ast[1]
  
  if func.tag == 'Id' and func[1] == 'setmetatable' then
      --apply metatable index to our guy
      local toupdate = processExpr(ast[2], scope)
      local metatable = processExpr(ast[3], scope)
      if (toupdate and metatable and metatable.childs) then
        --we will resolve this into types for api and as "Inherits" at end of processing
        toupdate.metatable = metatable
      end
      return toupdate
  elseif func.tag == 'Id' and func[1] == 'require' and ast[2].tag == 'String' then
      --apply metatable index to our guy
      local file = ast[2][1]
      return processFile(file, scope['::global'])
  else
     local funcdef = processExpr(func,scope)
     --funcdef.type = "function"
     local args = {}
     for i = 2,#ast do
       table.insert( args, processExpr(ast[i],scope))
     end
     return resolveFunctionValueType(funcdef, args, ast,scope)
  end
  
end


function processInvoke(ast, scope)
  local funcname = ast[2][1]
  local tabledef = processExpr(ast[1],scope)
  
  if tabledef and isTable(tabledef)  then
    if not tabledef.childs then
      zbsConvertToClass(tabledef)
    end
    
    if tabledef.childs[funcname] then
      return resolveValuetype(ast, tabledef.childs[funcname].valuetype, scope)
    else
      local ures = zbsUnresolvedIdent(ast[2], funcname, scope)
      ures.type = "method"
      tabledef.childs[funcname] = ures
      return resolveValuetype(ast, tabledef.childs[funcname].valuetype, scope)
    end
  end
end


function processTable(ast, scope)
  --local recs = ast[1]
 
  local t = zbsClass(ast, scope)
  for i, v in ipairs(ast) do
    local comment = getFirstComment(v)
    if v.tag == 'Pair' then
      
      local val = processExpr(v[2], scope)
      if (val == nil) then
        print("oops")
        processExpr(v[2], scope)
      end
      
      if (val ~= nil) then
        val.comment = comment
        val.description = comment or val.description
      end
      t.childs[v[1][1]] = val
      
    else
      
      local val = processExpr(v, scope)
      if (val ~= nil) then
        val.comment = comment
        val.description =  comment or val.description
      end
      t.childs[#t.childs] = val
      
    end
  end
  
  return t
end

function processIdent(ast, scope)
  --return value info from ident
  local name = ast[1]
  
  local val = scope[name]
  
  --resolve any complex value types
  if val and val.type == "value" and val.valuetype and type(val.valuetype) == "string" and val.valuetype ~= "string" and val.valuetype ~= "number" 
    and val.valuetype ~= "boolean"
  then
    local deref = scope[val.valuetype]
    if deref then
      val = deref
    end
  end
  
  if not val then
    --create an unresolved type (must have come from outside this file)
    val = zbsUnresolvedIdent(ast,name, scope)
    scope['::global'][name] = val
  end
  
  return val
end

function processIndex(ast, scope) 
  local tbl = processExpr(ast[1], scope)
  local idx = ast[2]
  --ensure they are both idents or strings
  if (tbl and isTable(tbl)) then
    if (idx.tag == 'String' or idx.tag == 'Number') then 
      if not tbl.childs then
        zbsConvertToClass(tbl)
      end
      local val = tbl.childs[idx[1]]
      if val then
        return val
      else
        tbl.childs[idx[1]] = zbsUnresolvedIdent(ast, idx[1], scope)
        return tbl.childs[idx[1]]
      end
    else
      --too complex
      return zbsComplexTableAccess(ast, scope)
    end
  else
    print("index on non table")
  end
end

function processOp(ast, scope)
  local op = ast[1]
  local left = ast[2]
  local right = ast[3]
  if op == 'and' then
    --and takes value from right
    return processExpr(right, scope)
  end
  
  if op == 'or' then
    local currentBest = processExpr(left, scope)
    return bestReturn(currentBest, processExpr(right, scope))
  end
  
  if op == 'len' then
    return processExpr(left, scope)
  end
  
  if op == 'not' or op == 'eq' or op == 'lt' or op == 'le' or op == 'gt' or op =='ge' then
    return zbsValue(ast,"boolean", scope) 
  end
  
  if op == 'concat' then
    return zbsValue(ast,"string", scope) 
  end
  
  if op == 'add' or op == 'sub' or op == 'mul' or op =='div' or op == 'mod' or op == 'pow' then
    return zbsValue(ast,"boolean", scope) 
  end
end



local function processSet(ast, scope)
  local comment = getFirstComment(ast)
  local vars = ast[1]
  local vals = ast[2]
  for i,v in ipairs(vars) do
    if v.tag == 'Id' then
      local name = v[1]
      if vals[i] then
        local val = processExpr(vals[i], scope)
        if val then
          val.comment = comment
          val.description = comment
          setInScope(scope, name, val)
        end
      end
    end
    
    if v.tag == 'Index' then
      local tbl = v[1]
      local idx = v[2]
      --ensure they are both idents or strings, otherwise we are boned (at least until I get ambitious)
      if (tbl.tag == 'Id' and (idx.tag == 'String' or idx.tag == 'Number')) then
        local val = vals[i] ~= nil and processExpr(vals[i], scope)
        if (val) then
          if not scope[tbl[1]] then 
            scope[tbl[1]] = zbsClass(v, scope)
            scope[tbl[1]].inferred = true
            scope[tbl[1]].unresolved = true
          end
          if not scope[tbl[1]].childs then
            --we must have thought this was a value at one stage, turn it into a table
            zbsConvertToClass(scope[tbl[1]], scope)
            scope[tbl[1]].inferred = true
            scope[tbl[1]].unresolved = true
          end
          local existing = scope[tbl[1]].childs[idx[1]]
          val.comment = comment
          val.description = comment or  val.description
          if existing  then
            if not val.unresolved then
              updateValue(existing, val)
            end
          else
            scope[tbl[1]].childs[idx[1]] = val
          end
          
        end
      end
    end
  end
end

local function processLocal(ast, scope)
  local comment = getFirstComment(ast)
  local vars = ast[1]
  local vals = ast[2]
  for i,v in ipairs(vars) do
    local name = v[1]
    local val =  zbsUnresolvedIdent(ast, name, scope)
    
    if (vals[i]) then
      val = processExpr(vals[i], scope) or val
    end
    if type(val) ~= "table" then
      print("oops")
    end
    val.comment = comment
    val.description = comment or val.description 
    scope[name] = val
  end
end


local function processOverride(t, action, args)
    if not isTable(t) then return end
    
    if     action == "inherits" then
      
      if not t.inherits then 
        zbsConvertToClass(t)
      end
      local inherits = {}
      t.inherits:gsub("(%S+)", function (parent) inherits[parent] = true end)
      for parent in args:gmatch("(%S+)") do
        if not inherits[parent] then
          t.inherits = t.inherits.." "..parent
        end
      end
      
    elseif action == "valuetype" then
      
      if args then
        t.valuetype = args
      end
    
    end
  
end

local function findByName(name, scope)
  local dummy = { childs = scope }
  local v = dummy
  for seg in name:gmatch("([^%.]+)") do 
    if not (isTable(v) and v.childs and v.childs[seg]) then
      return nil
    end
    v = v.childs[seg]
  end
  return v
end


local function processCommentApiOverride(ast, scope)
  local comment = getFirstComment(ast)
  
  if comment then
    for ident, action, args in (comment):gmatch("@api (%S+) (%S+) ([^\n]*)") do
      --find ident
      print("processing comment override ",ident, action, args)
      local t = findByName(ident, scope)
      if t then
        processOverride(t, action, args)
      else
        print("Couldnt find identifier for api override",ident)
      end
      
    end
  end
end




local function processStatement(ast, scope)
  --process comment override  
  processCommentApiOverride(ast, scope['::global'])
  
  
  local tag = ast.tag
  local switch = {
    ['Do'] = function() return processBlock(ast[1], scope) end,
    ['Set'] = function() processSet(ast, scope) end,
    ['Local'] = function() processLocal(ast, scope) end,
    ['Localrec'] = function() 
        processLocal(ast, scope)
      end, 
    ['Return'] = function() 
        if (ast[1]) then return processExpr(ast[1], scope) end
      end,
  
    ['While'] = function() return processBlock(ast[2], scope) end,
    ['Repeat'] = function() return processBlock(ast[1], scope) end,
    ['If'] = function() return processIf(ast, scope) end,
    ['Fornum'] = function() return processFornum(ast, scope) end,
    ['Forin'] = function() return processForin(ast, scope) end,
    ['Invoke'] = function() processInvoke(ast, scope) end,
    ['Call'] = function() processCall(ast, scope) end,
  }
  local action = switch[tag]
  local res = nil
  if action then res = action() end
  return res
end



function processFornum(ast, scope)
  local newscope = pushScope(scope, "Fornum")
  newscope[ast[1][1]] = zbsValue(ast, "number", scope)
  return processBlock(ast[#ast], newscope)
end

function processForin(ast, scope)
  local newscope = pushScope(scope, "Forin")
  local vars = ast[1]
  local it = ast[2][1]
  
  --check for pairs/ipairs call and assume iterator over first arg
  if it.tag == 'Call' and it[1].tag == 'Id' then
    if it[1][1] == 'ipairs' then
      newscope[vars[1][1]] = zbsValue(ast, "number", scope)
    else 
      newscope[vars[1][1]] = zbsValue(ast, "string",scope) --assume string keys
    end
    --val type
    if vars[2] then
      local valtype = processExpr(it[2], scope)
      if valtype and isTable(valtype) and valtype.childs then
        local typeset = false
        for kt, vt in pairs(valtype.childs) do
          newscope[vars[2][1]] = vt
          typeset = true
          break
        end
        if not typeset then
          newscope[vars[2][1]] = zbsUnresolvedFunctionResult(it[1],nil,scope) 
        end
      else
        newscope[vars[2][1]] = zbsUnresolvedFunctionResult(it[1],nil,scope) 
      end
    end
  else
    newscope[vars[1][1]] = zbsValue(ast, "iterresult", scope)
    if vars[2] then
      newscope[vars[2][1]] = zbsValue(ast, "iterresult", scope)
    end
  end
  
  return processBlock(ast[#ast], newscope)
end


function processBlock(ast, scope)
  local thisscope = pushScope(scope, "Block")
  --our best guess at return type
  local bestRet = nil
  
  for k,v in ipairs(ast) do
    local ret = processStatement(v, thisscope)
    bestRet = bestReturn(bestRet, ret)
  end

  return bestRet
end

function processIf(ast, scope)
--our best guess at return type
  local bestRet = nil
  local haselse = math.floor(#ast/2) < (#ast/2)
  
  for i = 2,#ast,2 do
    local ret = processBlock(ast[i], scope)
    bestRet = bestReturn(bestRet, ret)
  end
  
  if haselse then
    local ret = processBlock(ast[#ast], scope)
    bestRet = bestReturn(bestRet, ret)
  end
  
  return bestRet
end

function processFile(filename, scope)
  
  
  --find in cache
  local cached = scope[requirePrefix..filename]
  if cached then return cached end

  --do it the hard way
  local fileast = astFromFile(filename..'.lua')
  
  --dumptags(fileast,0,4)
  local requireResult = processBlock(fileast, scope)
  
  --require returns bool if no explicit return value
  if requireResult == nil then
    requireResult = zbsValue(fileast, "boolean", scope)
  end
  
  local requirekey = requirePrefix..filename
  scope[requirekey] = requireResult
  
  return zbsValue(fileast, requirekey, scope)
end


local function typesInScope(scope, prefix)

  local visited = {}
  
  local function walkTypesInScopeGen(scope, prefix)
    if not prefix then prefix = '' end
    for k,v in pairs(scope) do
      if type(k) == "number" or ( type(k) == "string" and not k:match("^::")) and not visited[v] then
        visited[v] = true
        coroutine.yield(prefix..k,v)
        if v.childs then
          walkTypesInScopeGen(v.childs, prefix..k..".")
        end
      end
    end
  end

   
   return coroutine.wrap(function() walkTypesInScopeGen(scope, prefix) end)
end



function BuildApiFromStartFile(startdir, filename, globalsFromExternalProjects)
  startDir = startdir
  local globalscope = createGlobalScope() --new global scope for this file
  setmetatable(globalscope, { __index = globalsFromExternalProjects }) --fall back to globals from other files

  processFile(filename, globalscope)

  local function GenNames(scope)
    
    local resolvedThisTime
    local unresolved = scope
    
    local typeToName = {}

    for k,v in typesInScope(globalsFromExternalProjects) do
      typeToName[v] = k
    end
    
    local globalmt = getmetatable(globalsFromExternalProjects)
    if globalmt and globalmt.__index then
      for k,v in typesInScope(globalmt.__index) do
        typeToName[v] = k
      end
    end
    

    for k,v in typesInScope(scope) do
        typeToName[v] = k
    end
    
    repeat
      local resolved = {}
      --flatten value types
      for k,v in typesInScope(scope) do
          local valuet = v.valuetype
          
          if valuet and (type(valuet) == "function") then
            valuet = valuet() --no args since this must be a lib call
            v.valuetype = valuet
          end
          
          if valuet and (v.type == "function" or v.type == "method" or v.type == "value") then
            
            local n = nil
            if type(valuet) == "string" then
              n = valuet
            elseif valuet.type == "value" then
              n = valuet.valuetype
            else
              n = typeToName[valuet]
            end
            
            if n == nil then
              n = k.."::returntype"
              resolved[n] = valuet 
              typeToName[valuet] = n
            end
            
            v.valuetype = n
          else
            v.valuetype = nil --we don't have one
          end
      end
      --append new type names to scope now that we are out of our iterator
      resolvedThisTime = 0
      for k,v in pairs(resolved) do
        resolvedThisTime = resolvedThisTime + 1
        scope[k] = v
      end
     
      local resolvedmt = {}
      
      --apply meta table
      for k,v in typesInScope(scope) do
            --flatten metatable
            local metaidx = isTable(v) and v.metatable and v.metatable.childs and v.metatable.childs.__index and v.metatable.childs.__index
            
            if metaidx then
              --first resolve children that are present in metatable
              local inheritedFuncs = {}
              for k1,c in pairs(v.childs) do
                if c.unresolved and metaidx.childs and metaidx.childs[k1] then
                  table.insert(inheritedFuncs, k1)
                end
              end
              for _, k1 in ipairs(inheritedFuncs) do
                v.childs[k1] = nil
              end
              
              --resolve name
              local inherits = typeToName[metaidx]
              if not inherits then
                inherits =  k.."::mt"
                resolvedmt[inherits] = metaidx --new name
                typeToName[metaidx] = inherits
              end
              v.metatable = nil
              v.inherits = (v.inherits or "").." "..inherits
            end
      end
      
      
      local metatablesadded = 0
      for k,v in pairs(resolvedmt) do
        resolvedThisTime = resolvedThisTime + 1
        metatablesadded = metatablesadded + 1
        scope[k] = v
        resolved[k] = v
      end
      
      unresolved = resolved
      
    until resolvedThisTime == 0

  end
  GenNames(globalscope)
  cleanGlobalScope(globalscope)
  
  return globalscope
end




-- test

local function dump(t)
  local serpent = require('serpent')
  print(serpent.block(t))
end

local function dumptags(ast, depth, maxdepth)
  for k=1,depth do
    io.write("  |")
  end
  if (not isTable(ast)) then
    io.write("-"..tostring(ast).."\n")
    return
  else
    io.write("-["..(ast.tag or "nil").."]\n")
  end
  
  if (depth >= maxdepth) then 
    return 
  end
  
  local nextdepth = depth+1
    for k,v in ipairs(ast) do
      dumptags(v,nextdepth,maxdepth)
    end
  
end



local function dumpNames(scope)
  for k,v in typesInScope(scope) do
    --if not v.unresolved then
      print(k,"\t\t\t", v.type, v.inherits, "\t\t ", v.valuetype )
   -- end
  end
end


--local baselib = dofile('D:/daviddownloads/zerobranestudio/api/lua/baselib.lua')
--local moai = dofile('D:/daviddownloads/zerobranestudio/api/lua/moai.lua')
--setmetatable(moai, { __index = baselib }) --fall back to moai

--local globalscope = BuildApiFromStartFile("scratch4", moai ) --GetApi("lua").ac.childs











