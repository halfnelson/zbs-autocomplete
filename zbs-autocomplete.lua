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




function Plugin:onProjectLoad(projdir) 
--  ProjectSetInterpreter("pito")
   -- TODO, gen api
end


function Plugin:rebuildAutocomplete() 
  --while developing we should reload the rebuilder
  dofile(package_root..GetPathSeparator()..'apigen.lua')
 -- BuildApiFromStartFile(filename, globalsFromExternalProjects)
 --start file 
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
  
  self:addMainMenu()
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
  instance = Plugin
}

return plugin



