global assert, collectgarbage, error, gemdos, ipairs, loadfile, pairs,
  require, string, table, type, warn

local <const> k_WindRefs = require("gembindl.utility.windrefs")
local <const> k_RCache = require("gembindl.utility.rcache")
local <const> k_Menu = k_RCache.require("gembindl.utility.menu")
local <const> k_Path = k_RCache.require("gembindl.utility.disk.path")
local <const> k_Text = k_RCache.require("gembindl.utility.disk.text")
local aesdefs = k_RCache.require("gembindl.utility.defs.aesdefs")
local msgdefs = k_RCache.require("gembindl.utility.defs.msgdefs")
local <const> k_meba_show = aesdefs.meba_show
local <const> k_meba_erase = aesdefs.meba_erase
local <const> k_grmo_arrow = aesdefs.grmo_arrow
local <const> k_grmo_hourglass = aesdefs.grmo_hourglass
local <const> k_evmu_keybd = aesdefs.evmu_keybd
local <const> k_evmu_mesag = aesdefs.evmu_mesag
local <const> k_evmu_timer = aesdefs.evmu_timer
local <const> k_evbu_control = aesdefs.evbu_control
local <const> k_evme_mn_selected = aesdefs.evme_mn_selected

local <const> k_mesag_internal = msgdefs.mesag_internal
local <const> k_msg_error = msgdefs.msg_error
local <const> k_err_wicr = msgdefs.err_wicr

aesdefs = nil
msgdefs = nil

-- The JInit job is indicated in insstlua.lua as the launch job. It is
-- therefore the controlling job of the application, and is used to
-- display the menu bar and add handlers for each selectable menu entry.
local <const> JInit = {
  -- The job's evmu_mask value is checked against evnt_multi happend
  -- bits to determine if the job's dispatch function will be called.
  -- JInit:dispatch is called for keybd, mesag and timer events.
  evmu_mask = k_evmu_keybd | k_evmu_mesag | k_evmu_timer,
}

-- init_job. Initialises the job
-- Returns:
--   1) boolean: true if job initialised successfully
function JInit:init_job()
  -- Get the loop the job is part of
  local <const> loop = self.loop
  local <const> rsrc, aes, vdi, cdefs =
    loop.rsrc, loop.aes, loop.vdi, loop.cdefs
  self.aes_ = aes

  -- Obtain the screen resolution by opening a virtual workstation for
  -- the screen and checking workout.
  local <const> gh = aes:graf_handle()
  local <const> svwk_h, workout = vdi:v_opnvwk(gh,
    { 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 2 })
  local svwk_x_max, svwk_y_max = workout[1], workout[2]
  vdi:v_clsvwk(svwk_h)

  -- If screen resolution is too small then display an error and finish
  -- The program is designed for ST medium or higher resolution. The
  -- dialogue boxes are too large to be displayed in low resolution.
  if svwk_x_max < 639 or svwk_y_max < 199 then
    -- The alert message is a free string within the resource file.
    self.aes_:form_alert(1,
      rsrc:reads(rsrc:frstr_offset(cdefs.fs1_e_res), nil, 0))
    -- Returning false from init_jobs tells Loop that the job failed
    -- to initialise.
    return false
  end

  -- Create new menu
  local <const> menu = k_Menu:new(rsrc, aes, cdefs.menu1)
  self.menu_ = menu

  -- Add menu handlers for each selectable menu entry
  menu:add_handler(cdefs.mn1_desk, cdefs.mn1_aboutinsst,
    self.mn1_aboutinsst_handler)
  menu:add_handler(cdefs.mn1_file, cdefs.mn1_load_config,
    self.mn1_load_config_handler)
  menu:add_handler(cdefs.mn1_file, cdefs.mn1_save_config,
    self.mn1_save_config_handler)
  menu:add_handler(cdefs.mn1_file, cdefs.mn1_install,
    self.mn1_install_handler)
  menu:add_handler(cdefs.mn1_file, cdefs.mn1_quit,
    self.mn1_quit_handler)
  menu:add_handler(cdefs.mn1_help, cdefs.mn1_readme,
    self.mn1_readme_handler)
  menu:add_handler(cdefs.mn1_help, cdefs.mn1_logger,
    self.mn1_logger_handler)

  -- Show the menu bar
  local <const> status =
    aes:menu_bar(self.menu_:menu_tree_addr(), k_meba_show)
  if status == 0 then
    -- Failed to show the menu bar. Indicate to Loop that the
    -- initialisation has failed.
    return false
  end

  -- Change the mouse pointer to an arrow.
  aes:graf_mouse(k_grmo_arrow)

  -- Set callback function to be invoked as each module is required.
  -- Changes the mouse pointer to hourglass/busy bee before the require
  -- then back to an arrow afterwards.
  k_RCache.set_on_require(
    function(is_before, modname)
      if is_before then
        return aes:graf_mouse(k_grmo_hourglass)
      else
        return aes:graf_mouse(k_grmo_arrow)
      end
    end)

  -- Add the logger job. This is mainly used to display debug messages
  -- during development, but has been left in for informational messages.
  -- The high bias means it dispatches after lower bias jobs, as they may
  -- have output logging information.
  local <const> JLogger = k_RCache.require("gembindl.utility.jobs.jlogger")
  self.logger_job_ = JLogger:new()
  self.loop:add_job(self.logger_job_, "logger", 65535)

  -- Redirect Lua 'warn' output to the logger 
  self.logger_job_:set_warn(true)

  -- Output the first message to be logged
  self.logger_job_:log("Logger started.")
  -- Log that pressing ^J will list the jobs
  self.logger_job_:log("^J to list jobs.")
  -- Log that pressing ^G will manually trigger a garbage collection
  self.logger_job_:log("^G to garbage collect.")
  -- Log that pressing ^K will show the total memory in use by Lua in KiB
  -- Note: this does not include memory allocated by Memory userdata using
  -- gemdos.Malloc or gemdos.utility.allocm calls.
  self.logger_job_:log("^K to show total memory use in KiB.")

  -- Configuration controlling what is installed.
  self.config_ = {
    -- programs
    prgs = true,      -- Programs are installed
    prgs_path = "",   -- The destination path for programs
    -- modules
    mods = true,      -- Modules are installed
    mods_path = "",   -- The destination path for modules
    aes = true,       -- The AES module will be included
    vdi = true,       -- The VDI module will be included
    utility = true,   -- The Utility module will be included
    sources = true    -- The source code module will be included
  }

  -- Array which determines the order of saved values in the configuration
  -- file.
  self.config_order_ = {
    "prgs",
    "prgs_path",
    "mods",
    "mods_path",
    "aes",
    "vdi",
    "utility",
    "sources"
  }

  -- Load the default configuration. Load failures are not checked here.
  -- Any missing/bad configuration is discarded by load_config_.
  local <const> path = k_Path.join_path(self.loop.rsrc_dir, "INSTALL.CFG")
  self:load_config_(path)

  -- Set the timer. This is the timeout for evnt_multi timer events.
  self.loop:set_timeout(1000)

  return true
end

-- term_job. Terminates the job
-- Returns:
--   1) boolean: true if job terminated successfully
function JInit:term_job()
  -- Remove the on_require callback (One of its upvalues refers to the
  -- aes instance)
  k_RCache.set_on_require(nil)

  -- Erase the menu bar
  local <const> status =
    self.aes_:menu_bar(self.menu_:menu_tree_addr(), k_meba_erase)
  return status > 0
end

-- dispatch. Dispatches events to the menu
-- Inputs:
--   1) integer: happened: the events that happened
--   2) integer: mx: mouse x position
--   3) integer: my: mouse y position
--   4) integer: button: buttons pressed
--   5) integer: keycode: the keycode
--   6) integer: clicks: the number of clicks
--   7) table: mesag: the mesag
function JInit:dispatch(
    happened, mx, my, button, shiftkey, keycode, clicked, mesag)
  local dispatch_menu = false
  if happened & k_evmu_keybd ~= 0 then
    -- Keyboard events are dispatched to the menu
    dispatch_menu = true

    -- Process any control-key combinations not handled by the menu
    if shiftkey & k_evbu_control ~= 0 then
      local <const> key = keycode & 0xff
      if key == 0x7 then
        -- ^G Manually trigger garbage collection
        self:collect_garbage_("collect")
      elseif key == 0xa then
        -- ^J List the jobs to the logger
        for j in self.loop:jobs() do
          self.logger_job_:log(
            "job_id: ", j.job_id, " name: '", j.job_name, "' bias: ", j.bias)
        end
      elseif key == 0xb then
        -- ^K Log the memory in use by Lua in KiB
        self.logger_job_:log("count: ", collectgarbage("count"))
      end
    end
  end
  if happened & k_evmu_timer ~= 0 then
    -- Timer has fired. Perform a garbage collection step. Not really
    -- necessary because Lua garbage collects automatically as the program
    -- runs. But instead of being blocked in evnt_multi doing nothing the
    -- collector is explicitly stepped here.
    self:collect_garbage_("step")
  end
  if happened & k_evmu_mesag ~= 0 then
    if mesag[1] == k_evme_mn_selected then
      -- menu selected message is dispatched to the menu
      dispatch_menu = true
    elseif mesag[1] == k_mesag_internal then
      -- If a Mesag was received and it was an internal message then handle
      -- it. Currently this is only used to display an alert if window
      -- creation failed (e.g. because too many window handles are in use).
      self:handle_mesag_internal_(mesag)
    end
  end
  if dispatch_menu then
    -- Dispatch the event (keyboard or mesag) to the menu
    return self.menu_:dispatch(self,
      happened, mx, my, button, shiftkey, keycode, clicked, mesag)
  end
end

function JInit:collect_garbage_(collect_type)
  if collect_type == "collect" then
    -- Full collection
    self.aes_:graf_mouse(k_grmo_hourglass)
    local <const> pre = collectgarbage("count")
    collectgarbage(collect_type)
    local <const> post = collectgarbage("count")
    self.aes_:graf_mouse(k_grmo_arrow)
    self.logger_job_:log("gc: ", pre, " -> ", post)
  elseif collect_type == "step" then
    -- Step collection
    collectgarbage(collect_type, 0)
  end
end

function JInit:handle_mesag_internal_(mesag)
  if mesag[4] == k_msg_error and mesag[5] == k_err_wicr then
    -- window create failed message. The alert is displayed using call_modal
    -- WindRefs function. WindRefs holds references to Wind instances. The
    -- call_modal function informs each Wind instance before the modal
    -- dialogue box is displayed, and after the modal dialogue box is removed.
    -- This is used by JDlgView to undraw an edit cursor before displaying
    -- the modal dialogue, and to redraw the edit cursor when it has been
    -- removed.
    return k_WindRefs:call_modal(function()
      local <const> rsrc = self.loop.rsrc
      local <const> cdefs = self.loop.cdefs
      self.aes_:form_alert(1,
        rsrc:reads(rsrc:frstr_offset(cdefs.fs12_e_wicr), nil, 0))
      end)
  end
end

-- Handler for about dialogue
function JInit:mn1_aboutinsst_handler(happened, mx, my,
    button, shiftkey, keycode, clicked, mesag_tbl)
  if self.jabout_ then
    -- About job already exists, top the window
    self.jabout_:set_top()
  else
    -- Create about job for about dialogue
    local <const> JAbout = k_RCache.require("jabout")
    local jabout = JAbout:new()
    -- Add the about job to the loop. The passed function is called with
    -- the result of job initialisation and termination ("init" and "term"
    -- update_type): it is used to store/clear the reference to the job.
    self.loop:add_job(jabout, "about", 0,
      function(job, update_type, result)
        if not result then
          return
        elseif update_type == "init" then
          -- JAbout initialised successfully
          self.jabout_ = job
        elseif update_type == "term" then
          -- JAbout terminated successfully
          self.jabout_ = nil
        end
      end)
  end
end

-- Load the configuration. It would be more usual in Lua to store the
-- configuration by serialising the configuration table into Lua, which
-- can then be loaded and parsed by the Lua parser. However the aim is to
-- be compatible with a parserless Lua, which can only load Lua bytecode.
-- So to keep the configuration file in a human readable format, loading
-- and saving of it is performed manually.
function JInit:load_config_(path)
  self.logger_job_:log("Loading cfg ", path)

  -- Load the file into lines table as an array of strings
  local ec, lines = k_Text.load_lines(path)
  if ec ~= 0 then
    self.logger_job_:log("Error ", ec, " loading cfg")
    return
  end

  -- Input each line of configuration, storing into a new config table
  local input_okay = true
  local <const> new_config = table.create(0, #self.config_order_)
  for k,v in ipairs(lines) do
    input_okay = input_okay and self:input_config_line_(new_config, v)
  end
  if input_okay then
    -- The configuration is okay, use it
    self.logger_job_:log("Loaded cfg")
    self.config_ = new_config
    -- Display the configuration to the Logger
    self:log_configuration_()
  else
    -- The configuration was bad, don't use it
    self.logger_job_:log("Failed to load cfg")
  end
  return input_okay
end

-- Handler for load configuration
function JInit:mn1_load_config_handler(happened, mx, my,
    button, shiftkey, keycode, clicked, mesag_tbl)
  -- Load config uses the file selector and can display an alert, so
  -- perform it modally via WindRefs. This ensures any JDlgView edit cursor
  -- is undrawn before the load operation and redrawn afterwards.
  return k_WindRefs:call_modal(function()
    -- Use the file selector to choose the configuration file to load
    local <const> status, cancel_ok, path, file =
      self.aes_:fsel_wrapper(
        self.loop.rsrc_dir, "INSTALL.CFG", "Load config")

    if status > 0 and cancel_ok == 1 then
      -- Combine the directory and file into a full file path
      local dir = k_Path.dir_from_path(path)
      local <const> fpath = k_Path.join_path(dir, file)
      -- Load the configuration from the file path
      if self:load_config_(fpath) then
        -- If the install job is running, it needs updating with the
        -- new configuration.
        if self.jinstall_ then
          -- Update the install job with the new configuration
          self.jinstall_:set_config(self.config_)
        end
      else
        -- Load configuration failed, display an alert
        local <const> rsrc, cdefs = self.loop.rsrc, self.loop.cdefs
        self.aes_:form_alert(1,
          rsrc:reads(rsrc:frstr_offset(cdefs.fs3_e_cload), nil, 0))
      end
    end
  end)
end

-- Output the configuration to the logger
function JInit:log_configuration_()
  for k,v in ipairs(self.config_order_) do
    local <const> config_value = self.config_[v]
    local config_value_str
    if type(config_value) == "boolean" then
      config_value_str = config_value and "true" or "false"
    elseif type(config_value) == "string" then
      config_value_str = config_value
    end
    self.logger_job_:log(v, "=", config_value_str)
  end
end

-- Inputs a line of configuration. Each line is in the format key=value.
function JInit:input_config_line_(new_config, line)
  -- Determine line key and line value
  local <const> lk, lv = string.match(line, "^([_a-z]+)=(.*)")
  if lk then
    -- Found a key. Check its type by checking the existing configuration
    -- value for that key. That constrains the allowed value: for boolean
    -- true or false is allowed. For strings, the value is used as is.
    local<const> value_type = type(self.config_[lk])
    -- Determine the value
    local v
    if value_type == "boolean" then
      if lv == "true" then
        v = true
      elseif lv == "false" then
        v = false
      end
    elseif value_type == "string" then
      v = lv
    end
    -- If the value was valid/found then use it
    if v ~= nil then
      new_config[lk] = v
      -- Configuration line was valid
      return true
    end
  end
  -- Not a valid configuration line
  return false
end

-- Handler for save configuration
function JInit:mn1_save_config_handler(happened, mx, my,
    button, shiftkey, keycode, clicked, mesag_tbl)
  -- Save config uses the file selector and can display an alert, so
  -- use WindRefs call_modal.
  return k_WindRefs:call_modal(function()
    local <const> status, cancel_ok, path, file =
      self.aes_:fsel_wrapper(
        self.loop.rsrc_dir, "INSTALL.CFG", "Save config")

    if status > 0 and cancel_ok == 1 then
      local dir = k_Path.dir_from_path(path)
      local <const> fpath = k_Path.join_path(dir, file)
      -- Save the configuration
      self.logger_job_:log("Saving cfg ", fpath)
      -- Create a gemdos file to store the cofiguration
      local <const> ec, fud <close> =
        gemdos.Fcreate(fpath, gemdos.const.Fattrib.none)
      if ec < 0 then
        -- Could not create file
        self.logger_job_:log("Failed to create cfg")
        -- Display error alert
        self.aes_:form_error(-ec - 31)
      else
        -- Output config keys and values
        local output_okay = true
        for k,v in ipairs(self.config_order_) do
          output_okay = output_okay and self:output_config_line_(fud, v)
        end
        if output_okay then
          -- Configuration output okay
          self.logger_job_:log("Saved cfg")
        else
          -- Failed to save configuration, display an alert.
          self.logger_job_:log("Failed to save cfg")
          local <const> rsrc, cdefs = self.loop.rsrc, self.loop.cdefs
          self.aes_:form_alert(1,
            rsrc:reads(rsrc:frstr_offset(cdefs.fs2_e_csave), nil, 0))
        end
      end
    end
  end)
end

-- Function to output a config key and value
function JInit:output_config_line_(fud, key)
  local <const> v = self.config_[key]
  local <const> value_type = type(v)
  local s
  -- Generate key=value string for boolean or string value
  if value_type == "boolean" then
    s = string.format("%s=%s\r\n", key, v and "true" or "false")
  elseif value_type == "string" then
    s = string.format("%s=%s\r\n", key, v)
  end
  assert(s ~= nil)
  -- Write the string to the file
  local <const> ec = fud:writes(s)
  return ec == #s
end

-- Handler for install dialogue
function JInit:mn1_install_handler(happened, mx, my,
    button, shiftkey, keycode, clicked, mesag_tbl)
  if self.jinstall_ then
    -- Install job already exists, top the window
    self.jinstall_:set_top()
  else
    -- Create install job for install dialogue
    local <const> JInstall = k_RCache.require("jinstall")
    local jinstall = JInstall:new()
    -- Set the configuration for the install job
    jinstall:set_config(self.config_)
    -- Set the menu for the installer (so items can be enabled/disabled)
    jinstall:set_menu(self.menu_)
    -- Add the install job to the loop
    self.loop:add_job(jinstall, "install", 0,
      function(job, update_type, result)
        if not result then
          return
        elseif update_type == "init" then
          -- JInstall initialised successfully
          self.jinstall_ = job
        elseif update_type == "term" then
          -- JInstall terminated successfully
          self.jinstall_ = nil
        end
      end)
  end
end

-- Handler for quit
function JInit:mn1_quit_handler(happened, mx, my,
    button, shiftkey, keycode, clicked, mesag_tbl)
  -- Is installation running? Check for existence of "copy" job.
  local <const> copy_job = self.loop:get_job_by_name("copy")
  -- If there is no copy job then stop. If there is a copy job then
  -- check with the copy job first.
  if not copy_job or copy_job:copy_dialog_preclosed() then
    -- Stop the loop. This will quit the program.
    self.loop:stop()
  end
end

-- Handler for readme
function JInit:mn1_readme_handler(happened, mx, my,
    button, shiftkey, keycode, clicked, mesag_tbl)
  if self.readme_jtxtview_ then
    -- Release notes txtview job already exists, top the window
    self.readme_jtxtview_:set_top()
  else
    local <const> path = k_Path.join_path(self.loop.rsrc_dir, "README.TXT")
    -- Load the readme into lines table as an array of strings.
    local <const> aes = self.aes_
    aes:graf_mouse(k_grmo_hourglass)
    local ec, lines = k_Text.load_lines(path)
    aes:graf_mouse(k_grmo_arrow)
    if ec ~= 0 then
      lines = { "Readme could not be loaded" }
      self.logger_job_:log("Error ", ec, " loading ", path)
    end

    -- Create txtview job to display the readme
    -- Add the lines to the txtview
    local <const> JTxtView = k_RCache.require("gembindl.utility.jobs.jtxtview")
    local txtview_job = JTxtView:new(lines)
    -- Set name of the window
    txtview_job:set_name("Readme")
    -- Add the job to the loop
    self.loop:add_job(txtview_job, "readme txtview", 0,
      function(job, update_type, result)
        if not result then
          return
        elseif update_type == "init" then
          -- JTxtView initialised successfully
          self.readme_jtxtview_ = job
        elseif update_type == "term" then
          -- JTxtView terminated successfully
          self.readme_jtxtview_ = nil
        end
      end)
  end
end

-- Handler for logger
function JInit:mn1_logger_handler(happened, mx, my,
    button, shiftkey, keycode, clicked, mesag_tbl)
  self.logger_job_:open_window()
end

return JInit
