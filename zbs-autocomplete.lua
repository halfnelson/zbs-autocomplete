--package paths
local homepath = (ide.osname == 'Windows') and os.getenv("USERPROFILE") or os.getenv("HOME")
local homepackages = homepath..GetPathSeparator()..'.zbstudio'..GetPathSeparator()..'packages'..GetPathSeparator()..'zbs-autocomplete'..GetPathSeparator()..'?.lua'

local zbs_package_dir = 'packages/zbs-autocomplete'
local zbs_user_package_dir = homepath..GetPathSeparator()..'.zbstudio'..GetPathSeparator()..'packages'..GetPathSeparator()..'zbs-autocomplete'

local package_root = zbs_package_dir
if wx.wxDir.Exists(zbs_user_package_dir) then
  package_root = zbs_user_package_dir
end

package.path =  package.path .. ';packages/zbs-autocomplete/?.lua;'..homepackages
--local ProjectManager = require("packages.zbs-moaiutil.lib.texturepackerproject")

local Plugin = {}

local md = require("mobdebug.mobdebug")

local function tableToLua(t)
  return md.line(t , {indent='  ', comment=false} )
end




local ID_AUTOCOMPLETE_REBUILD = ID("ID_AUTOCOMPLETE_REBUILD")
local ID_AUTOCOMPLETE_MENU = ID("ID_AUTOCOMPLETE_MENU")


function Plugin:onSave()
    self:rebuildAutocomplete()
end


function Plugin:onProjectLoad(projdir) 
   self:rebuildAutocomplete()
end


function Plugin:rebuildAutocomplete() 
  --while developing we should reload the rebuilder
  dofile(package_root..GetPathSeparator()..'apigen.lua')
 
  local startFile = ide:GetProjectStartFile()
  
  if (not startFile) then 
    DisplayOutputLn("Couldn't rebuild API, no startfile for project")
    return 
  end
 
  local startPath = GetPathWithSep(startFile).."?.lua"
  local nametmp = wx.wxFileName(startFile)
--  nametmp:ClearExt()
  local startName = nametmp:GetName()
  
  assert(not wx.wxFileName(startName):HasExt())
  
  --make sure we have a copy of the base api
  if not self.baseApi then
    ide.config.api = self.apisWithoutProject
    ReloadAPIs("lua")
    local api = {}
    for k,v in pairs(GetApi("lua").ac.childs) do
      api[k] = v
    end
    self.baseApi = api
  end
  
  
  
  local projectApi
  local success, err = xpcall(function()  projectApi = BuildApiFromStartFile(startPath, startName, self.baseApi) end,
      function(err)  DisplayOutputLn(debug.traceback()); return err end
  )
  
  -- build project api if possible
  if success then
      
      -- add project to the list of api's
      local apisWithProject = {};
      for k,v in pairs(self.apisWithoutProject) do
        apisWithProject[k] = v
      end
      table.insert(apisWithProject,"project")
      ide.config.api = apisWithProject
      
      --put our output where reload can find it (the cache)
      ide.apis['lua']['project'] = projectApi --todo, actually output this to a file to make project loads faster

      ReloadAPIs("lua")
      DisplayOutputLn("Project api creation/rebuild complete")
  else
      --revert to our last known good one if it exists
      if (ide.apis['lua']['project']) then
        ide.config.api = apisWithProject
        ReloadAPIs("lua")
      end
      
      DisplayOutputLn("Error reloading/creating project api")
      DisplayOutputLn(err)
  end

end

function Plugin:addMainMenu()
  local menubar = ide:GetMenuBar()
  local menuOpts = {
    { ID_AUTOCOMPLETE_REBUILD, TR("Rebuild Autocomplete"), TR("Rebuild Autocomplete") },
  }
  
  self.mainMenu = wx.wxMenu(menuOpts)
  menubar:Append(self.mainMenu, "Autocomplete")
  
  self.mainMenu:Connect( ID_AUTOCOMPLETE_REBUILD, wx.wxEVT_COMMAND_MENU_SELECTED, function () 
    self:rebuildAutocomplete()  
  end)
    
end


function Plugin:onRegister() 
  self.apisWithoutProject =  ide.config.api
  self:addMainMenu()
  self.baseApi = false
  DisplayOutputLn("Plugin registered")
end


local plugin = {
  name = "ZBS Moai Util",
  description = "Moai Hostutil GUI for ZBS",
  author = "David Pershouse",
  version = 0.1,
  dependencies = 1.10,
  onRegister = function() Plugin:onRegister() end,
  onProjectLoad = function(self, projectDir) Plugin:onProjectLoad(projectDir) end,
  onEditorSave = function() Plugin:onSave() end,
  instance = Plugin
}

return plugin



