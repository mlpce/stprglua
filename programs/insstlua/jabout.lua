global assert, require, setmetatable, warn

local <const> k_RCache = require("gembindl.utility.rcache")
local aesdefs = k_RCache.require("gembindl.utility.defs.aesdefs")
local <const> k_obdr_root = aesdefs.obdr_root
local <const> k_obch_selected = aesdefs.obch_selected
local <const> k_obch_normal = aesdefs.obch_normal
aesdefs = nil

local <const> JAbout = {
}

-- new. Create a new JAbout instance
-- Inputs:
--   1) table: o: optional table to use as instance
function JAbout:new(o)
  o = o or {}
  o.evmu_mask = 0
  self.__index = self
  return setmetatable(o, self)
end

-- init_job. Initialises the job
-- Returns:
--   1) boolean: true if job initialised successfully
function JAbout:init_job()
  self.aes_ = self.loop.aes
  self.rsrc_ = self.loop.rsrc
  return self:open_dialog_()
end

-- term_job. Terminates the job
-- Returns:
--   1) boolean: true if job terminated successfully
function JAbout:term_job()
  if self.jdlgview_ then
    self.loop:del_job(self.jdlgview_)
    self.jdlgview_ = nil
  end
  return true
end

-- set_top. Tops the dialog
function JAbout:set_top()
  if self.jdlgview_ then
    return self.jdlgview_:set_top()
  end
end

-- open_dialog_. Opens the dialog window
function JAbout:open_dialog_()
  -- Create a dlgview for the dialogue
  local <const> JDlgView = k_RCache.require("gembindl.utility.jobs.jdlgview")
  local jdlgview = JDlgView:new()
  jdlgview:set_name("About")
  local <const> form_objn = self.loop.cdefs.fm3
  -- Set the form object number. There is no edit box.
  jdlgview:set_dialog(form_objn)

  -- Only has ok button
  jdlgview:set_on_form_evnt(
    function(view, continuing, clicked_objn, edited_objn)
      return continuing
    end)

  -- Unselect all selected items
  for obj, offset in self.rsrc_:objects(form_objn, k_obdr_root) do
    if self.rsrc_:obj_peek_state(offset) == k_obch_selected then
     self.rsrc_:obj_poke_state(offset, k_obch_normal)
    end
  end

  -- Add the dlgview job to the loop
  self.loop:add_job(jdlgview, "about dlgview", 0,
    function(job, update_type, result)
      if update_type == "init" then
        if result then
          -- JDlgView initialised successfully
          self.jdlgview_ = job
        else
          -- JDlgView failed to initialise
          self.loop:del_job(self)
        end
      elseif update_type == "term" then
        if result then
          -- JDlgView terminated successfully
          self.jdlgview_ = nil
          return self.loop:del_job(self)
        end
      end
    end)
  return true
end

return JAbout
