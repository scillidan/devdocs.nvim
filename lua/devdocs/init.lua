local M = {}

local config = require("devdocs.config")
local docs = require("devdocs.docs")
local db = require("devdocs.db")
local browser = require("devdocs.browser")
local picker = require("devdocs.picker")
local utils = require("devdocs.utils")

local _docs = {}
local _entries = nil

local function notify(msg, level)
  level = level or vim.log.levels.INFO
  print("[devdocs] " .. msg)
  vim.schedule(function()
    vim.notify("[devdocs] " .. msg, level)
  end)
end

local function warn(msg)
  notify(msg, vim.log.levels.WARN)
end

local function err(msg)
  notify(msg, vim.log.levels.ERROR)
end

local function discover_docs()
  _docs = docs.discover({
    include = config.opts.include_documents,
    exclude = config.opts.exclude_documents,
  })
  if #_docs == 0 then
    local dirs = config.opts.search_dirs
    local dir_list = {}
    for _, d in ipairs(dirs) do
      table.insert(dir_list, utils.normalize_path(vim.fn.expand(d)))
    end
    warn("No DevDocs found in: " .. table.concat(dir_list, ", "))
  end
end

local function load_entries_async(callback)
  if _entries then
    callback(_entries)
    return
  end

  local all = {}
  local pending = #_docs
  if pending == 0 then
    _entries = all
    callback(all)
    return
  end

  for _, doc in ipairs(_docs) do
    vim.schedule(function()
      local entries = db.load_entries(doc)
      for _, e in ipairs(entries) do
        table.insert(all, e)
      end
      pending = pending - 1
      if pending == 0 then
        table.sort(all, function(a, b)
          return a.name:lower() < b.name:lower()
        end)
        _entries = all
        callback(all)
      end
    end)
  end
end

local function get_word()
  local cword = vim.fn.expand("<cword>")
  if not cword or cword == "" then
    return nil
  end
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local left, right = col, col
  while left > 1 and line:sub(left - 1, left - 1):match("[%w_%.:]") do
    left = left - 1
  end
  while right < #line and line:sub(right + 1, right + 1):match("[%w_%.:]") do
    right = right + 1
  end
  local expanded = line:sub(left, right)
  if expanded:lower():find(cword:lower(), 1, true) then
    return expanded
  end
  return cword
end

local function refresh_docs()
  vim.schedule(function()
    _entries = nil
    discover_docs()
  end)
end

local function install_doc(slug, callback)
  if not docs.is_available(slug) then
    err("Doc not available: " .. slug)
    if callback then
      callback(false)
    end
    return
  end
  if docs.is_installed(slug) then
    if callback then
      callback(true)
    end
    return
  end
  docs.install(slug, function(ok)
    if ok then
      refresh_docs()
    else
      err("Failed to install: " .. slug)
    end
    if callback then
      callback(ok)
    end
  end)
end

local function install_ensure_list(list, index, fail_count)
  index = index or 1
  fail_count = fail_count or 0
  if index > #list then
    if fail_count > 0 then
      warn(string.format("ensure_installed: %d/%d ok, %d failed", #list - fail_count, #list, fail_count))
    end
    return
  end
  local slug = list[index]
  install_doc(slug, function(ok)
    if not ok then
      fail_count = fail_count + 1
    end
    install_ensure_list(list, index + 1, fail_count)
  end)
end

function M.setup(opts)
  config.setup(opts)
  utils.mkdir(config.data_dir())
  utils.mkdir(config.docs_dir())
  discover_docs()

  vim.schedule(function()
    if utils.exists(config.metadata_file()) then
      docs.load_metadata()
    end
    docs.fetch_metadata(false, function()
      refresh_docs()
      local ensure = config.opts.ensure_installed or {}
      if #ensure > 0 then
        install_ensure_list(ensure)
      end
    end)
  end)

  vim.api.nvim_create_user_command("DevDocs", function(args)
    M.open()
  end, { nargs = 0, desc = "Open DevDocs picker" })

  vim.api.nvim_create_user_command("DevDocsInstall", function(args)
    local slug = args.args ~= "" and args.args or nil
    if slug then
      if not docs.is_available(slug) then
        docs.fetch_metadata(false, function()
          docs.load_metadata()
          if docs.is_available(slug) then
            install_doc(slug)
          else
            err("Doc not available: " .. slug)
          end
        end)
        return
      end
      install_doc(slug)
    else
      local meta = docs.load_metadata()
      if not meta.list or #meta.list == 0 then
        warn("No metadata. Run :DevDocsFetch first")
        return
      end
      local items = {}
      for _, doc in ipairs(meta.list) do
        local label = doc.name
        if doc.version and doc.version ~= "" then
          label = label .. " ~" .. doc.version
        end
        label = label .. " (" .. doc.slug .. ")"
        table.insert(items, { label = label, value = doc.slug })
      end
      picker.select(items, {
        prompt = "Install DevDoc",
        on_select = function(item)
          if item then
            install_doc(item.value)
          end
        end,
      })
    end
  end, { nargs = "?", desc = "Install DevDocs" })

  vim.api.nvim_create_user_command("DevDocsUninstall", function(args)
    local slug = args.args ~= "" and args.args or nil
    if slug then
      docs.delete(slug)
      refresh_docs()
    else
      local installed = docs.installed()
      if #installed == 0 then
        warn("No DevDocs installed")
        return
      end
      local items = {}
      for _, s in ipairs(installed) do
        table.insert(items, { label = s, value = s })
      end
      picker.select(items, {
        prompt = "Uninstall DevDoc",
        on_select = function(item)
          if item then
            docs.delete(item.value)
            refresh_docs()
          end
        end,
      })
    end
  end, { nargs = "?", desc = "Uninstall DevDocs" })

  vim.api.nvim_create_user_command("DevDocsUpdate", function(args)
    local slug = args.args ~= "" and args.args or nil
    if slug then
      docs.update(slug, function(ok)
        if ok then
          refresh_docs()
        else
          err("Failed to update: " .. slug)
        end
      end)
    else
      local installed = docs.installed()
      if #installed == 0 then
        warn("No DevDocs installed")
        return
      end
      local items = {}
      for _, s in ipairs(installed) do
        table.insert(items, { label = s, value = s })
      end
      picker.select(items, {
        prompt = "Update DevDoc",
        on_select = function(item)
          if item then
            docs.update(item.value, function(ok)
              if not ok then
                err("Failed to update: " .. item.value)
              else
                refresh_docs()
              end
            end)
          end
        end,
      })
    end
  end, { nargs = "?", desc = "Update DevDocs" })

  vim.api.nvim_create_user_command("DevDocsUpdateAll", function()
    M.update_all()
  end, { nargs = 0, desc = "Update all DevDocs" })

  vim.api.nvim_create_user_command("DevDocsFetch", function()
    docs.fetch_metadata(true, function()
      refresh_docs()
    end)
  end, { nargs = 0, desc = "Fetch DevDocs metadata" })

  vim.api.nvim_create_user_command("DevDocsLookup", function(args)
    M.lookup(args.args ~= "" and args.args or nil)
  end, { nargs = "?", desc = "Look up word in DevDocs" })
end

function M.open()
  load_entries_async(function(entries)
    if #entries == 0 then
      warn("No entries loaded. Install with :DevDocsInstall")
      return
    end
    local ok, perr = pcall(picker.open, entries, {
      query = "",
      docsets = _docs,
      on_select = browser.open,
    })
    if not ok then
      err("Failed to open picker: " .. tostring(perr))
    end
  end)
end

function M.lookup(word)
  word = word or get_word()
  if not word or word == "" then
    warn("No word under cursor")
    return
  end

  load_entries_async(function(entries)
    if #entries == 0 then
      warn("No entries loaded")
      return
    end
    local ok, perr = pcall(picker.open, entries, {
      query = word,
      docsets = _docs,
      on_select = browser.open,
    })
    if not ok then
      err("Failed to open picker: " .. tostring(perr))
    end
  end)
end

function M.update_all()
  local installed = docs.installed()
  if #installed == 0 then
    warn("No DevDocs installed")
    return
  end

  local failed = 0
  local total = #installed
  local function run(index)
    if index > total then
      if failed > 0 then
        warn(string.format("%d/%d updated, %d failed", total - failed, total, failed))
      end
      return
    end
    docs.update(installed[index], function(ok)
      if not ok then
        failed = failed + 1
      end
      run(index + 1)
    end)
  end

  run(1)
end

function M.get_installed_docs()
  return docs.installed()
end

function M.get_doc_dir(slug)
  return config.docs_dir() .. "/" .. slug
end

return M
