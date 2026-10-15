global assert, collectgarbage, ipairs, package, pairs, require, setmetatable, string, warn

local <const> WindRefs = require("gembindl.utility.windrefs")
local <const> k_RCache = require("gembindl.utility.rcache")
local <const> k_Path = k_RCache.require("gembindl.utility.disk.path")
local aesdefs = k_RCache.require("gembindl.utility.defs.aesdefs")
local <const> k_obdr_root = aesdefs.obdr_root
local <const> k_obch_selected = aesdefs.obch_selected
local <const> k_obch_normal = aesdefs.obch_normal
local <const> k_meie_disable = aesdefs.meie_disable
aesdefs = nil

local <const> JInstall = {
}

-- new. Create a new JInstall instance
-- Inputs:
--   1) table: o: optional table to use as instance
function JInstall:new(o)
  o = o or {}
  o.evmu_mask = 0
  self.__index = self
  return setmetatable(o, self)
end

-- init_job. Initialises the job
-- Returns:
--   1) boolean: true if job initialised successfully
function JInstall:init_job()
  self.aes_ = self.loop.aes
  self.rsrc_ = self.loop.rsrc
  self.logger_job_ = self.loop:get_job_by_name("logger")
  assert(self.logger_job_)
  assert(self.config_)
  return self:open_dialog_()
end

-- term_job. Terminates the job
-- Returns:
--   1) boolean: true if job terminated successfully
function JInstall:term_job()
  if self.jdlgview_ then
    self.loop:del_job(self.jdlgview_)
    self.jdlgview_ = nil
  end
  return true
end

-- set_top. Tops the dialog
function JInstall:set_top()
  if self.jdlgview_ then
    return self.jdlgview_:set_top()
  end
end

-- set_config. Sets the config for the installer
-- Inputs:
--   1): table: config: the configuration
function JInstall:set_config(config)
  -- Determine if the configuration has changed
  local changed = false
  if self.config_ then
    for k,v in pairs(config) do
      if self.config_[k] ~= v then
        changed = true
      end
    end
  end

  -- Set the configuration table
  self.config_ = config

  -- Update state if the configuration has changed
  if self.jdlgview_ and changed then
    self:update_prgs_path_(self.config_.prgs_path)
    self:update_mods_path_(self.config_.mods_path)
    self:update_toggle_boxes_()
    self.jdlgview_:view_send_redraw()
  end
end

-- set_menu. Sets the menu for the installer
-- Inputs:
--   1) table: menu: the menu
function JInstall:set_menu(menu)
  self.menu_ = menu
end

-- open_dialog_. Opens the dialog window
function JInstall:open_dialog_()
  assert(self.config_)

  -- Create a dlgview for the dialogue
  local <const> JDlgView = k_RCache.require("gembindl.utility.jobs.jdlgview")
  local jdlgview = JDlgView:new()
  jdlgview:set_name("Install")
  local <const> cdefs = self.loop.cdefs
  -- Set the form object number and edit box object number
  jdlgview:set_dialog(cdefs.fm1, cdefs.fm1_prgs_dest)
  -- Callback invoked when form event occurs
  jdlgview:set_on_form_evnt(
    function(view, continuing, clicked_objn, edited_objn)
      return self:process_form_event_(continuing, clicked_objn, edited_objn)
    end)

  local <const> rsrc = self.rsrc_

  -- Unselect all selected items
  for obj, offset in rsrc:objects(cdefs.fm1, k_obdr_root) do
    if rsrc:obj_peek_state(offset) == k_obch_selected then
      rsrc:obj_poke_state(offset, k_obch_normal)
    end
  end

  -- Get offset of fm1_prgs_dest from start of resource
  self.fm1_prgs_dest_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_prgs_dest)
  -- Get offset of fm1_prgs_dest tedinfo
  self.fm1_prgs_dest_tedinfo_offset_ =
    rsrc:obj_tedinfo_offset(self.fm1_prgs_dest_offset_)
  -- Get text from fm1_prgs_dest tedinfo
  local txt, txtlen =
    rsrc:tedinfo_read_text(self.fm1_prgs_dest_tedinfo_offset_)
  self.fm1_prgs_dest_max_string_len_ = txtlen - 1
  -- Update fm1_prgs_dest text
  self:update_prgs_path_(self.config_.prgs_path)

  -- Get offset of fm1_mods_dest from start of resource
  self.fm1_mods_dest_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_mods_dest)
  -- Get offset of fm1_mods_dest tedinfo
  self.fm1_mods_dest_tedinfo_offset_ =
    rsrc:obj_tedinfo_offset(self.fm1_mods_dest_offset_)
  -- Get text from fm1_mods_dest tedinfo
  txt, txtlen =
    rsrc:tedinfo_read_text(self.fm1_mods_dest_tedinfo_offset_)
  self.fm1_mods_dest_max_string_len_ = txtlen - 1
  -- Update fm1_mods_dest text
  self:update_mods_path_(self.config_.mods_path)

  -- Get offset of fm1_prgs_fsel
  self.fm1_prgs_fsel_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_prgs_fsel)
  -- Get offset of fm1_mods_fsel
  self.fm1_mods_fsel_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_mods_fsel)

  -- Get offsets of toggle boxes
  self.fm1_inst_prgs_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_inst_prgs)
  self.fm1_inst_mods_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_inst_mods)
  self.fm1_inst_aes_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_inst_aes)
  self.fm1_inst_vdi_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_inst_vdi)
  self.fm1_inst_utility_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_inst_utility)
  self.fm1_inst_sources_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_inst_sources)

  -- Update the toggle boxes
  self:update_toggle_boxes_()

  -- Write the default Lua path split into the three text object tedinfos
  local <const> path_objn_t = {
    cdefs.fm1_dft_luapath1,
    cdefs.fm1_dft_luapath2,
    cdefs.fm1_dft_luapath3
  }

  local s = package.path
  for k,v in ipairs(path_objn_t) do
    local <const> offset = rsrc:tree_obj_offset(cdefs.fm1, v)
    local <const> tedinfo_offset = rsrc:obj_tedinfo_offset(offset)
    local <const> txt, txtlen = rsrc:tedinfo_read_text(tedinfo_offset)
    local <const> split = string.sub(s, 1, #txt)
    s = string.sub(s, #split + 1, -1)
    rsrc:tedinfo_write_text(tedinfo_offset, split)
  end

  -- Install button offset
  self.fm1_install_offset_ =
    rsrc:tree_obj_offset(cdefs.fm1, cdefs.fm1_install)

  -- Add the dlgview job to the loop
  self.loop:add_job(jdlgview, "install dlgview", 0,
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

-- Updates the dialogue toggle box states
function JInstall:update_toggle_boxes_()
  local <const> rsrc = self.rsrc_
  -- Poke state into the toggle boxes
  rsrc:obj_poke_state(self.fm1_inst_prgs_offset_,
    self.config_.prgs and k_obch_selected or k_obch_normal)
  rsrc:obj_poke_state(self.fm1_inst_mods_offset_,
    self.config_.mods and k_obch_selected or k_obch_normal)
  rsrc:obj_poke_state(self.fm1_inst_aes_offset_,
    self.config_.aes and k_obch_selected or k_obch_normal)
  rsrc:obj_poke_state(self.fm1_inst_vdi_offset_,
    self.config_.vdi and k_obch_selected or k_obch_normal)
  rsrc:obj_poke_state(self.fm1_inst_utility_offset_,
    self.config_.utility and k_obch_selected or k_obch_normal)
  rsrc:obj_poke_state(self.fm1_inst_sources_offset_,
    self.config_.sources and k_obch_selected or k_obch_normal)
end

-- Callback for form events
function JInstall:process_form_event_(continuing, clicked_objn, edited_objn)
  local <const> cdefs = self.loop.cdefs
  local <const> rsrc = self.rsrc_
  local txt, txtlen
  if edited_objn == cdefs.fm1_prgs_dest then
    -- Programs destination edit box
    txt, txtlen =
      rsrc:tedinfo_read_text(self.fm1_prgs_dest_tedinfo_offset_)
    -- Update configuration with programs path
    self.config_.prgs_path = txt
  elseif edited_objn == cdefs.fm1_mods_dest then
    -- Modules destination edit box
    txt, txtlen =
      rsrc:tedinfo_read_text(self.fm1_mods_dest_tedinfo_offset_)
    -- Update configuration with modules path
    self.config_.mods_path = txt
  end
  if clicked_objn == -1 then
    return continuing
  elseif clicked_objn == cdefs.fm1_prgs_fsel then
    -- Button for programs destination file selector
    local <const> status, cancel_ok, path, file =
      self:fsel_(self.loop.init_dir, "", "Choose prgs directory")
    -- Change button state back to normal
    rsrc:obj_poke_state(self.fm1_prgs_fsel_offset_, k_obch_normal)
    if status > 0 and cancel_ok == 1 then
      local <const> ec, norm =
        k_Path.normalize_path(k_Path.dir_from_path(path))
      assert(ec == 0)
      -- Update dialogue box with new programs path
      self:update_prgs_path_(norm)
    end
    continuing = true
  elseif clicked_objn == cdefs.fm1_mods_fsel then
    -- Button for modules destination file selector
    local <const> status, cancel_ok, path, file =
      self:fsel_(self.loop.init_dir, "", "Choose mods directory")
    -- Change button state back to normal
    rsrc:obj_poke_state(self.fm1_mods_fsel_offset_, k_obch_normal)
    if status > 0 and cancel_ok == 1 then
      local <const> ec, norm =
        k_Path.normalize_path(k_Path.dir_from_path(path))
      assert(ec == 0)
      -- Update dialogue box with new modules path
      self:update_mods_path_(norm)
    end
    continuing = true
  elseif clicked_objn == cdefs.fm1_inst_prgs then
    -- Install programs toggle
    self.config_.prgs =
      rsrc:obj_peek_state(self.fm1_inst_prgs_offset_) == k_obch_selected
  elseif clicked_objn == cdefs.fm1_inst_mods then
    -- Install modules toggle
    self.config_.mods =
      rsrc:obj_peek_state(self.fm1_inst_mods_offset_) == k_obch_selected
  elseif clicked_objn == cdefs.fm1_inst_aes then
    -- Install AES module toggle
    self.config_.aes =
      rsrc:obj_peek_state(self.fm1_inst_aes_offset_) == k_obch_selected
  elseif clicked_objn == cdefs.fm1_inst_vdi then
    -- Install VDI module toggle
    self.config_.vdi =
      rsrc:obj_peek_state(self.fm1_inst_vdi_offset_) == k_obch_selected
  elseif clicked_objn == cdefs.fm1_inst_utility then
    -- Install Utility module toggle
    self.config_.utility =
      rsrc:obj_peek_state(self.fm1_inst_utility_offset_) == k_obch_selected
  elseif clicked_objn == cdefs.fm1_inst_sources then
    -- Install Sources module toggle
    self.config_.sources =
      rsrc:obj_peek_state(self.fm1_inst_sources_offset_) == k_obch_selected
  elseif clicked_objn == cdefs.fm1_install then 
    if not self:check_config_for_install_() then
      -- Unselect the install button
      rsrc:obj_poke_state(self.fm1_install_offset_, k_obch_normal)
      continuing = true
    else
      -- Start the JCopy job
      local <const> JCopy = k_RCache.require("jcopy")
      local jcopy = JCopy:new()
      -- Set the menu for the copy (so items can be enabled)
      jcopy:set_menu(self.menu_)
      -- Set the configuration for the copy job
      jcopy:set_config(self.config_)

      -- Disable the menu items responsible for loading config,
      -- saving config and opening the install dialogue.
      local <const> menu_tree_addr = self.menu_:menu_tree_addr()
      local status = self.aes_:menu_ienable(
        menu_tree_addr, cdefs.mn1_load_config, k_meie_disable)
      assert(status > 0)
      status = self.aes_:menu_ienable(
        menu_tree_addr, cdefs.mn1_save_config, k_meie_disable)
      assert(status > 0)
      status = self.aes_:menu_ienable(
        menu_tree_addr, cdefs.mn1_install, k_meie_disable)
      assert(status > 0)

      -- Add the copy job
      self.loop:add_job(jcopy, "copy")
    end
  end
  return continuing
end

-- Check if the configuration is valid for the install
function JInstall:check_config_for_install_()
  local <const> cdefs = self.loop.cdefs
  local <const> rsrc = self.rsrc_

  -- Check something is enabled to be installed
  local <const> module_chosen = self.config_.aes or
    self.config_.vdi or self.config_.utility or
    self.config_.sources
  if not (self.config_.prgs or (self.config_.mods and module_chosen)) then
    -- Nothing enabled. Display alert.
    WindRefs:call_modal(function()
    self.loop.aes:form_alert(1,
      rsrc:reads(rsrc:frstr_offset(cdefs.fs8_e_in_nothing), nil, 0))
    end)
    return false
  end

  local ec, norm_path = 0
  if self.config_.prgs then
    -- Programs are configured to install. Normalise prgs_path.
    ec, norm_path = k_Path.normalize_path(self.config_.prgs_path)
    if ec == 0 then
      -- Normalisation succeeded
      self.config_.prgs_path = norm_path
    else
      -- Normalisation failed, log the error code
      self.logger_job_:log("Error ", ec, " normalizing program install path")
      -- Display an alert
      WindRefs:call_modal(function()
      self.loop.aes:form_alert(1,
        rsrc:reads(rsrc:frstr_offset(cdefs.fs4_e_norm_ppath), nil, 0))
      end)
    end
  end

  if ec == 0 and self.config_.mods then
    -- Modules are configured to install. Normalise mods_path.
    ec, norm_path = k_Path.normalize_path(self.config_.mods_path)
    if ec == 0 then
      -- Normalisation succeeded
      self.config_.mods_path = norm_path
    else
      -- Normalisation failed, log the error code
      self.logger_job_:log("Error ", ec, " normalizing modules install path")
      -- Display an alert
      WindRefs:call_modal(function()
      self.loop.aes:form_alert(1,
        rsrc:reads(rsrc:frstr_offset(cdefs.fs5_e_norm_mpath), nil, 0))
      end)
    end
  end

  if ec == 0 and self.config_.prgs then
    -- Programs are configured to install.
    -- Check the programs destination path.
    local <const> get_path_ec, old_path = k_Path.get_path()
    if get_path_ec == 0 then
      ec = k_Path.set_path(self.config_.prgs_path)
      k_Path.set_path(old_path)
      if ec ~= 0 then
        self.logger_job_:log("Error ", ec, " checking program install path")
        -- Could not change to programs destination path. Display alert.
        WindRefs:call_modal(function()
        self.loop.aes:form_alert(1,
          rsrc:reads(rsrc:frstr_offset(cdefs.fs6_e_chck_ppath), nil, 0))
        end)
      end
    end
  end

  if ec == 0 and self.config_.mods then
    -- Modules are configured to install.
    -- Check the modules destination path.
    local <const> get_path_ec, old_path = k_Path.get_path()
    if get_path_ec == 0 then
      ec = k_Path.set_path(self.config_.mods_path)
      k_Path.set_path(old_path)
      if ec ~= 0 then
        self.logger_job_:log("Error ", ec, " checking modules install path")
        -- Could not change to modules destination path. Display alert.
        WindRefs:call_modal(function()
        self.loop.aes:form_alert(1,
          rsrc:reads(rsrc:frstr_offset(cdefs.fs7_e_chck_mpath), nil, 0))
        end)
      end
    end
  end

  -- If ec is zero the check succeeded
  return ec == 0
end

-- Call file selector with call_modal
function JInstall:fsel_(dir, file, title)
  return WindRefs:call_modal(function()
      return self.aes_:fsel_wrapper(dir, file, title)
    end)
end

-- Update config prgs_path and update tedinfo text
function JInstall:update_prgs_path_(path)
  self.config_.prgs_path = string.sub(path,
    1, self.fm1_prgs_dest_max_string_len_)
  self.rsrc_:tedinfo_write_text(
    self.fm1_prgs_dest_tedinfo_offset_,
    self.config_.prgs_path)
end

-- Update config mods_path and update tedinfo text
function JInstall:update_mods_path_(path)
  self.config_.mods_path = string.sub(path,
    1, self.fm1_mods_dest_max_string_len_)
  self.rsrc_:tedinfo_write_text(
    self.fm1_mods_dest_tedinfo_offset_,
    self.config_.mods_path)
end

return JInstall
