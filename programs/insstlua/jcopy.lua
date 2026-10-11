global assert, coroutine, debug, ipairs, require, setmetatable,
  string, table, tostring, warn, gemdos

local <const> k_dir_attribute = gemdos.const.Fattrib.dir
local <const> k_EFILNF = gemdos.const.Error.EFILNF
local <const> k_Fsfirst = gemdos.Fsfirst
local <const> k_Fdelete = gemdos.Fdelete
local <const> k_Dcreate = gemdos.Dcreate

local <const> WindRefs = require("gembindl.utility.windrefs")
local <const> k_RCache = require("gembindl.utility.rcache")
local <const> k_DirCopy = k_RCache.require("gembindl.utility.disk.dircopy")
local <const> k_DirScan = k_RCache.require("gembindl.utility.disk.dirscan")
local <const> k_FileCopy = k_RCache.require("gembindl.utility.disk.filecopy")
local <const> k_Path = k_RCache.require("gembindl.utility.disk.path")
local aesdefs = k_RCache.require("gembindl.utility.defs.aesdefs")
local <const> k_obdr_root = aesdefs.obdr_root
local <const> k_obch_selected = aesdefs.obch_selected
local <const> k_obch_normal = aesdefs.obch_normal
local <const> k_meie_enable = aesdefs.meie_enable
local <const> k_evmu_mesag = aesdefs.evmu_mesag
local <const> k_allocm = gemdos.utility.allocm
local <const> k_premud_alloc_size = 16384

aesdefs = nil

local <const> JCopy = {
}

-- new. Create a new JCopy instance
-- Inputs:
--   1) table: o: optional table to use as instance
function JCopy:new(o)
  o = o or {}
  -- Copy coroutine is resumed on mesag dispatch
  o.evmu_mask = k_evmu_mesag
  self.__index = self
  return setmetatable(o, self)
end

-- set_config. Sets the config for the copy
-- Inputs:
--   1): table: config: the configuration
function JCopy:set_config(config)
  self.config_ = config
end

-- set_menu. Sets the menu for the copy
-- Inputs:
--   1) table: menu: the menu
function JCopy:set_menu(menu)
  self.menu_ = menu
end

-- init_job. Initialises the job
-- Returns:
--   1) boolean: true if job initialised successfully
function JCopy:init_job()
  self.aes_ = self.loop.aes
  self.rsrc_ = self.loop.rsrc
  self.rsrc_dir_ = self.loop.rsrc_dir

  -- Get the logger job
  self.logger_job_ = self.loop:get_job_by_name("logger")
  assert(self.logger_job_)

  -- Allocate memory for the premud
  local <const> ec_alloc_size, premud = k_allocm(k_premud_alloc_size)
  if ec_alloc_size < 0 then
    self.logger_job_:log("Could not allocate premud")
    return false
  end

  self.premud_ = premud

  -- Create the coroutine for copying the files
  self.co_ = coroutine.create(function(...) return self:copy_(...) end)
  return self:open_dialog_()
end

function JCopy:generate_copy_items_()
  local <const> items = table.create(7)
  self.items_ = items
  if self.config_.prgs then
    -- Programs
    items[#items + 1] = "LUA.PRG"
    items[#items + 1] = "LUAB.PRG"
    items[#items + 1] = "LUAC.TTP"
  end

  if self.config_.mods then
    -- Modules
    if self.config_.aes then
      items[#items + 1] = "GEMBINDL\\AES.LUA"
    end
    if self.config_.vdi then
      items[#items + 1] = "GEMBINDL\\VDI.LUA"
    end
    if self.config_.utility then
      items[#items + 1] = "GEMBINDL\\UTILITY"
    end
    if self.config_.sources then
      items[#items + 1] = "SOURCES"
    end
  end
end

function JCopy:count_copy_items_()
  -- Function to count directories and files to copy
  local <const> cdefs = self.loop.cdefs
  local fn = function(path, descending, dirs, files)
    if descending then
      self.num_dirs_ = self.num_dirs_ + #dirs
      self.num_files_ = self.num_files_ + #files
      -- Update dir count
      if #dirs > 0 then
        self:update_dir_count_(self.num_dirs_)
        -- Send redraw for the dir count object
        self.jdlgview_:send_object_redraw(cdefs.fm2_dir_count)
      end

      -- Update file count
      if #files > 0 then
        self:update_file_count_(self.num_files_)
        -- Send redraw for the file count object
        self.jdlgview_:send_object_redraw(cdefs.fm2_file_count)
      end

      coroutine.yield(0)
    end
    return self.abort_
  end

  local <const> items = self.items_
  for k,v in ipairs(items) do
    local <const> path = k_Path.join_path(self.rsrc_dir_, v)
    local <const> attrib = gemdos.Fattrib(path, 0, 0)
    if attrib < 0 then
      self.logger_job_:log("ec ", attrib, " path ", path)
      return attrib
    end
    if attrib & k_dir_attribute ~= 0 then
      -- A directory recursively
      self.logger_job_:log("D: ", path)
      local ec = k_DirScan.dir_scan(path, "*.*", true, fn)
      if ec ~= 0 then
        return ec
      end
    else
      -- A single file
      self.logger_job_:log("F: ", path)
      self.num_files_ = self.num_files_ + 1
      self:update_file_count_(self.num_files_)
      -- Send redraw for the file count object
      self.jdlgview_:send_object_redraw(cdefs.fm2_file_count)
      coroutine.yield(0)
    end
    if self.abort_ ~= 0 then
      return self.abort_
    end
  end
  return 0
end

function JCopy:do_copy_items_()
  -- Callback for FileCopy function
  local <const> cdefs = self.loop.cdefs
  local <const> copy_file_fn = function(file_size, bytes_read, bytes_written)
    if file_size == bytes_written then
      -- A complete file has been copied
      self.num_files_done_ = self.num_files_done_ + 1
      self:update_file_count_(self.num_files_ - self.num_files_done_)
    end

    -- Send redraw for file count
    self.jdlgview_:send_object_redraw(cdefs.fm2_file_count)
    coroutine.yield(0)

    return self.abort_
  end

  -- Callback for directory copy function
  local <const> copy_dir_fn = function(operation, src_path, dst_path,
      file_size, bytes_read, bytes_written)
    if operation == "dcreate" or operation == "dfound" then
      -- A directory has been created or discovered
      self.num_dirs_done_ = self.num_dirs_done_ + 1
      self:update_dir_count_(self.num_dirs_ - self.num_dirs_done_)
      -- Send redraw for directory done count
      self.jdlgview_:send_object_redraw(cdefs.fm2_dir_count)
      coroutine.yield(0)
    elseif operation == "data" then
      return copy_file_fn(file_size, bytes_read, bytes_written)
    end

    return self.abort_
  end

  -- Create destination subdirectories if needed
  if self.config_.mods then
    local dir_create_path
    -- AES.LUA, VDI.LUA and UTILITY directory are copied into GEMBINDL dir
    if self.config_.aes or self.config_.vdi or self.config_.utility then
      -- create GEMBINDL directory
      dir_create_path =
        k_Path.join_path(self.config_.mods_path, "GEMBINDL")
      local ec = self:dir_create_(dir_create_path)
      if ec ~= 0 then
        self.logger_job_:log("dir_create_ returned: ", ec)
        self.logger_job_:log("Could not create ", dir_create_path)
        return ec
      end
      if self.config_.utility then
        -- create UTILITY subdirectory
        dir_create_path =
          k_Path.join_path(self.config_.mods_path, "GEMBINDL\\UTILITY")
        local ec = self:dir_create_(dir_create_path)
        if ec ~= 0 then
          self.logger_job_:log("dir_create_ returned: ", ec)
          self.logger_job_:log("Could not create ", dir_create_path)
          return ec
        end
      end
    end
    if self.config_.sources then
      -- create SOURCES directory
      dir_create_path =
        k_Path.join_path(self.config_.mods_path, "SOURCES")
      local ec = self:dir_create_(dir_create_path)
      if ec ~= 0 then
        self.logger_job_:log("dir_create_ returned: ", ec)
        self.logger_job_:log("Could not create ", dir_create_path)
        return ec
      end
    end
  end

  local <const> items = self.items_
  for k,v in ipairs(items) do
    local <const> path = k_Path.join_path(self.rsrc_dir_, v)
    local <const> attrib = gemdos.Fattrib(path, 0, 0)
    if attrib < 0 then
      self.logger_job_:log("ec ", attrib, " path ", path)
      return attrib
    end
    if attrib & k_dir_attribute ~= 0 then
      -- A directory recursively. Directory copies are for modules.
      local <const> dst_path = k_Path.join_path(self.config_.mods_path, v)
      self.logger_job_:log("D: ", dst_path)
      local <const> ec = k_DirCopy.dir_copy(
        path, dst_path, "*.*", true, true, copy_dir_fn, self.premud_)
      if ec ~= 0 then
        self.logger_job_:log("dir_copy returned: ", ec)
        self.logger_job_:log("Could not copy ", dst_path)
        return ec
      end
    else
      -- A single file
      -- Determine correct dst_prepath for program or module
      local <const> leading, extension = k_Path.fname_split(v)
      local dst_prepath
      if extension == "PRG" or extension == "TTP" then
        dst_prepath = self.config_.prgs_path
      else
        dst_prepath = self.config_.mods_path
      end
 
      local <const> dst_path = k_Path.join_path(dst_prepath, v)
      self.logger_job_:log("F: ", dst_path)
      local <const> ec, msg = k_FileCopy.file_copy(
        path, dst_path, true, copy_file_fn, self.premud_)
      if ec ~= 0 then
        self.logger_job_:log("file_copy returned: ", ec, " msg ", msg)
        self.logger_job_:log("Could not copy ", dst_path)
        return ec
      end
    end
  end
  return 0
end

-- Update the tedinfo text for the installation message
function JCopy:update_install_message_(msg)
  self.rsrc_:tedinfo_write_text(
    self.fm2_install_msg_tedinfo_offset_,
    string.sub(msg, 1,
    self.fm2_install_msg_max_string_len_))
end

-- Update the tedinfo text for the directory count
function JCopy:update_dir_count_(count)
  -- Write the dir count into the tedinfo
  self.rsrc_:tedinfo_write_text(
    self.fm2_dir_count_tedinfo_offset_,
    string.sub(tostring(count), 1,
    self.fm2_dir_count_max_string_len_))
end

-- Update the tedinfo text for the file count
function JCopy:update_file_count_(count)
  -- Write the file count into the tedinfo
  self.rsrc_:tedinfo_write_text(
    self.fm2_file_count_tedinfo_offset_,
    string.sub(tostring(count), 1,
    self.fm2_file_count_max_string_len_))
end

-- Create a directory if it does not already exist
function JCopy:dir_create_(path)
  assert(k_Path.is_abs_path(path))

  -- Create the destination directory if it does not exist
  local ec, path_dta <const> = k_Fsfirst(path, k_dir_attribute)
  if ec == 0 then
    if path_dta:attr() & k_dir_attribute ~= 0 then
      self.logger_job_:log("Found dir: ", path)
    else
      -- File needs to to be deleted
      self.logger_job_:log("Deleting file: ", path)
      ec = k_Fdelete(path)
      if ec == 0 then
        -- And then the directory created
        return self:dir_create_(path)
      end
    end
  elseif ec == k_EFILNF then
    if string.len(path) > 3 then
      self.logger_job_:log("Creating dir: ", path)
      ec = k_Dcreate(path)
    else
      -- Root directory does not need to be created
      ec = 0
    end
  end

  if ec ~= 0 then
    self.logger_job_:log("Failed to find/create/delete ", path)
  end

  return ec
end

-- Copy function run in coroutine
function JCopy:copy_()
  self.num_dirs_ = 0
  self.num_files_ = 0
  self.num_dirs_done_ = 0
  self.num_files_done_ = 0
  self.abort_ = 0

  -- First the directories and files to be copied are counted
  local <const> rsrc = self.rsrc_
  local <const> cdefs = self.loop.cdefs

  self:update_dir_count_(self.num_dirs_)
  self:update_file_count_(self.num_files_)

  -- Generate the table of items to copy
  self:generate_copy_items_()

  -- Count the items
  self.logger_job_:log("Counting items...")
  self:update_install_message_(
    rsrc:reads(rsrc:frstr_offset(cdefs.fs13_counting), nil, 0))
  self.jdlgview_:send_object_redraw(cdefs.fm2_install_msg)

  local ec = self:count_copy_items_()
  if ec == 0 then
    -- Copy the items
    self.logger_job_:log("Copying items...")
    self:update_install_message_(
      rsrc:reads(rsrc:frstr_offset(cdefs.fs14_copying), nil, 0))
    self.jdlgview_:send_object_redraw(cdefs.fm2_install_msg)

    ec = self:do_copy_items_()
    if ec == 0 then
      self.logger_job_:log("Copy complete")
    end
  end

  -- Copy done. Clear coroutine reference.
  self.co_ = nil
  return ec
end

-- term_job. Terminates the job
-- Returns:
--   1) boolean: true if job terminated successfully
function JCopy:term_job()
  if self.jdlgview_ then
    self.loop:del_job(self.jdlgview_)
  end

  -- Free the premud
  self.premud_:free()

  -- Clear coroutine reference
  self.co_ = nil

  -- Re-enable menu items
  local <const> cdefs = self.loop.cdefs
  local <const> menu_tree_addr = self.menu_:menu_tree_addr()
  local status = self.aes_:menu_ienable(
    menu_tree_addr, cdefs.mn1_load_config, k_meie_enable)
  assert(status > 0)
  status = self.aes_:menu_ienable(
    menu_tree_addr, cdefs.mn1_save_config, k_meie_enable)
  assert(status > 0)
  status = self.aes_:menu_ienable(
    menu_tree_addr, cdefs.mn1_install, k_meie_enable)
  assert(status > 0)

  return true
end

-- set_top. Tops the dialog
function JCopy:set_top()
  if self.jdlgview_ then
    return self.jdlgview_:set_top()
  end
end

-- dispatch. Dispatch to the JCopy
-- Inputs:
--   1) integer: happened: the events that happened
--   2) integer: mx: mouse x position
--   3) integer: my: mouse y position
--   4) integer: button: buttons pressed
--   5) integer: keycode: the keycode
--   6) integer: clicks: the number of clicks
--   7) table: mesag: the mesag
function JCopy:dispatch(
    happened, mx, my, button, shiftkey, keycode, clicked, mesag)
  if self.co_ ~= nil then
    local status, ec = coroutine.resume(self.co_)
    local success = true
    if not status then
      -- Failed. ec is the error message.
      self.logger_job_:log("Coroutine failed: ", ec)
      if debug then
        -- Log the traceback of the failure
        local <const> traceback_str = debug.traceback(self.co_)
        for line in string.gmatch(traceback_str, "[^\r\n]+") do
          self.logger_job_:log((string.gsub(line, "\t", " ")))
        end
      end
      coroutine.close(self.co_)
      self.co_ = nil
      success = false
    elseif self.co_ == nil and ec ~= 0 then
      -- JCopy:copy_ completed, but with a numeric ec error code
      -- Indicating the copy was not successful
      self.logger_job_:log("Install failed: ", ec)
      success = false
    end
    if self.co_ == nil then
      -- JCopy:copy_ completed, display a success or error message
      WindRefs:call_modal(function()
        local <const> rsrc = self.rsrc_
        local <const> cdefs = self.loop.cdefs
        self.aes_:form_alert(1,
          rsrc:reads(rsrc:frstr_offset(
            success and cdefs.fs11_s_in_done or cdefs.fs9_e_in_fail),
            nil, 0))
        end)
    end
  end
  if not self.co_ then
    -- Job is complete
    self.loop:del_job(self)
  end
end

-- open_dialog_. Opens the dialog window
function JCopy:open_dialog_()
  -- Create a dlgview for the dialogue
  local <const> JDlgView = k_RCache.require("gembindl.utility.jobs.jdlgview")
  local jdlgview = JDlgView:new()
  jdlgview:set_name("Copy")
  local <const> cdefs = self.loop.cdefs
  -- Set the form object number. There is no edit box.
  jdlgview:set_dialog(cdefs.fm2)
  -- Callback invoked by Wind close mesag via view_preclose
  jdlgview:set_on_preclose(
    function(view) return self:copy_dialog_preclosed() end)
  local <const> rsrc = self.rsrc_
  -- Abort button needs to query user for abort
  jdlgview:set_on_form_evnt(
    function(view, continuing, clicked_objn, edited_objn)
      if clicked_objn == cdefs.fm2_button then
        -- Unselect button
        rsrc:obj_poke_state(
          rsrc:tree_obj_offset(cdefs.fm2, cdefs.fm2_button),
          k_obch_normal)
        -- Redraw the button
        self.jdlgview_:send_object_redraw(cdefs.fm2_button)
        -- Query abort using alert
        return not self:copy_dialog_preclosed()
      end
      return continuing
    end)

  -- Unselect all selected items
  for obj, offset in rsrc:objects(cdefs.fm2, k_obdr_root) do
    if rsrc:obj_peek_state(offset) == k_obch_selected then
      rsrc:obj_poke_state(offset, k_obch_normal)
    end
  end

  -- Get offset of fm2_install_msg from start of resource
  self.fm2_install_msg_offset_ =
    rsrc:tree_obj_offset(cdefs.fm2, cdefs.fm2_install_msg)
  -- Get offset of fm2_install_msg tedinfo
  self.fm2_install_msg_tedinfo_offset_ =
    rsrc:obj_tedinfo_offset(self.fm2_install_msg_offset_)
  -- Get text from fm2_install_msg tedinfo
  local txt, txtlen =
    rsrc:tedinfo_read_text(self.fm2_install_msg_tedinfo_offset_)
  self.fm2_install_msg_max_string_len_ = txtlen - 1

  -- Get offset of fm2_dir_count from start of resource
  self.fm2_dir_count_offset_ =
    rsrc:tree_obj_offset(cdefs.fm2, cdefs.fm2_dir_count)
  -- Get offset of fm2_dir_count tedinfo
  self.fm2_dir_count_tedinfo_offset_ =
    rsrc:obj_tedinfo_offset(self.fm2_dir_count_offset_)
  -- Get text from fm2_dir_count tedinfo
  local txt, txtlen =
    rsrc:tedinfo_read_text(self.fm2_dir_count_tedinfo_offset_)
  self.fm2_dir_count_max_string_len_ = txtlen - 1

  -- Get offset of fm2_file_count from start of resource
  self.fm2_file_count_offset_ =
    rsrc:tree_obj_offset(cdefs.fm2, cdefs.fm2_file_count)
  -- Get offset of fm2_file_count_ tedinfo
  self.fm2_file_count_tedinfo_offset_ =
    rsrc:obj_tedinfo_offset(self.fm2_file_count_offset_)
  -- Get text from fm2_file_count tedinfo
  local txt, txtlen =
    rsrc:tedinfo_read_text(self.fm2_file_count_tedinfo_offset_)
  self.fm2_file_count_max_string_len_ = txtlen - 1

  -- Add the dlgview job to the loop
  self.loop:add_job(jdlgview, "copy dlgview", 0,
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

-- Use an alert to check if copy should be aborted
function JCopy:copy_dialog_preclosed()
  local result
  WindRefs:call_modal(function()
    local <const> rsrc = self.rsrc_
    local <const> cdefs = self.loop.cdefs
    result = self.aes_:form_alert(1,
      rsrc:reads(rsrc:frstr_offset(cdefs.fs10_e_abort),
        nil, 0))
    end)

  if result == 1 then
    -- Abort the copy
    self.abort_ = 1
  end

  -- Don't close the jdlgview. The coroutine will check abort_ and
  -- finish itself.
  return false
end

return JCopy
