local M = {}
local config = require("devdocs.config")
local state = require("devdocs.state")
local utils = require("devdocs.utils")

local DOWNLOAD_BASE = "https://downloads.devdocs.io"
local METADATA_URL = "https://devdocs.io/docs.json"

local function tar_executable()
  if vim.fn.has("win32") == 1 then
    local win_tar = "C:/Windows/System32/tar.exe"
    if vim.fn.executable(win_tar) == 1 then
      return win_tar
    end
  end
  return "tar"
end

local _metadata = nil

local function slug_dir(slug)
  return config.docs_dir() .. "/" .. slug
end

local function slug_tar(slug)
  return config.docs_dir() .. "/" .. slug .. ".tar.gz"
end

local function notify(msg, level)
  level = level or vim.log.levels.INFO
  print("[devdocs] " .. msg)
  vim.schedule(function()
    vim.notify("[devdocs] " .. msg, level)
  end)
end

function M.fetch_metadata(force, callback)
  local missing = not utils.exists(config.metadata_file())
  if not force and not missing and not state.is_stale() then
    if callback then
      callback()
    end
    return
  end

  notify("Fetching DevDocs metadata" .. (force and " (force)" or "") .. " ...")
  utils.mkdir(config.data_dir())

  local timeout = config.opts.download_timeout
  local args = {
    "curl",
    "-sSL",
    "--connect-timeout",
    "10",
    "--max-time",
    tostring(timeout),
    "-o",
    config.metadata_file(),
    METADATA_URL,
  }

  local retries = config.opts.download_retries
  local attempt = 0

  local function run()
    attempt = attempt + 1
    vim.system(args, { text = false }, function(res)
      if res.code == 0 then
        _metadata = nil
        state.metadata_downloaded(os.time())
        if callback then
          callback()
        end
        return
      end
      if attempt < retries then
        notify("Metadata fetch failed, retry " .. attempt .. "/" .. retries, vim.log.levels.WARN)
        vim.defer_fn(run, 1000 * attempt)
        return
      end
      notify("Failed to fetch metadata: " .. (res.stderr or "unknown error"), vim.log.levels.ERROR)
      if callback then
        callback()
      end
    end)
  end

  run()
end

function M.load_metadata()
  if _metadata then
    return _metadata
  end
  local file = config.metadata_file()
  local data = utils.read_json(file)
  if type(data) ~= "table" then
    notify("No metadata file found at " .. file .. " — run :DevDocsFetch", vim.log.levels.WARN)
    _metadata = { list = {}, map = {} }
    return _metadata
  end
  local map = {}
  for _, doc in ipairs(data) do
    map[doc.slug] = doc
  end
  _metadata = { list = data, map = map }
  return _metadata
end

function M.available()
  local meta = M.load_metadata()
  return meta.list or {}
end

function M.find(slug)
  local meta = M.load_metadata()
  return meta.map and meta.map[slug]
end

function M.is_available(slug)
  return M.find(slug) ~= nil
end

function M.installed()
  return state.installed()
end

function M.is_installed(slug)
  local s = state.get(slug)
  return s and s.installed and utils.exists(slug_dir(slug) .. "/index.json")
end

function M.download_link(slug)
  return DOWNLOAD_BASE .. "/" .. slug .. ".tar.gz"
end

function M.download(slug, callback)
  if not M.is_available(slug) then
    notify("Doc not available: " .. slug, vim.log.levels.ERROR)
    if callback then
      callback(false)
    end
    return
  end

  utils.mkdir(config.docs_dir())
  local tar_path = slug_tar(slug)
  local timeout = config.opts.download_timeout
  local args = {
    "curl",
    "-sSL",
    "--connect-timeout",
    "10",
    "--max-time",
    tostring(timeout),
    "-C",
    "-",
    "-o",
    tar_path,
    M.download_link(slug),
  }

  state.set(slug, { downloading = true, installed = false })

  local retries = config.opts.download_retries
  local attempt = 0

  notify("Downloading " .. slug .. " ...")

  local function run()
    attempt = attempt + 1
    vim.system(args, { text = false }, function(res)
      if res.code == 0 then
        vim.schedule(function()
          M.extract(slug, callback)
        end)
        return
      end
      if attempt < retries then
        notify(slug .. " download failed, retry " .. attempt .. "/" .. retries, vim.log.levels.WARN)
        vim.defer_fn(run, 1000 * attempt)
        return
      end
      state.set(slug, { downloading = false, installed = false })
      notify("Failed to download " .. slug, vim.log.levels.ERROR)
      if callback then
        callback(false)
      end
    end)
  end

  run()
end

function M.extract(slug, callback)
  local tar_path = slug_tar(slug)
  local target_dir = slug_dir(slug)

  if utils.exists(target_dir) then
    vim.fn.delete(target_dir, "rf")
  end
  utils.mkdir(target_dir)

  local args = { tar_executable(), "-xzf", tar_path, "-C", target_dir }
  notify("Extracting " .. slug .. " ...")

  vim.system(args, { text = false }, function(res)
    vim.schedule(function()
      local ok = res.code == 0
      if ok then
        local info = M.find(slug) or {}
        state.set(slug, {
          installed = true,
          downloading = false,
          mtime = info.mtime or os.time(),
        })
        pcall(vim.fn.delete, tar_path)
      else
        state.set(slug, { installed = false, downloading = false })
        notify("Failed to extract " .. slug, vim.log.levels.ERROR)
      end
      if callback then
        callback(ok)
      end
    end)
  end)
end

function M.install(slug, callback)
  if M.is_installed(slug) then
    if callback then
      callback(true)
    end
    return
  end
  M.download(slug, callback)
end

function M.delete(slug)
  local dir = slug_dir(slug)
  if utils.exists(dir) then
    vim.fn.delete(dir, "rf")
  end
  local tar = slug_tar(slug)
  if utils.exists(tar) then
    vim.fn.delete(tar)
  end
  state.remove(slug)
end

function M.update(slug, callback)
  if not M.is_installed(slug) then
    notify(slug .. " is not installed", vim.log.levels.WARN)
    if callback then
      callback(false)
    end
    return
  end
  M.download(slug, callback)
end

function M.doc_info(slug)
  local info = M.find(slug) or {}
  return {
    slug = slug,
    name = info.name or slug,
    version = info.version,
    release = info.release,
    mtime = info.mtime,
    db_size = info.db_size,
    installed = M.is_installed(slug),
  }
end

local function build_exclude_set(list)
  if not list or #list == 0 then
    return nil
  end
  local set = {}
  for _, name in ipairs(list) do
    set[name:lower()] = true
  end
  return set
end

local function matches_include(include_list, slug, title)
  if not include_list then
    return true
  end
  for _, pat in ipairs(include_list) do
    local pl = pat:lower()
    if slug:lower() == pl or title:lower() == pl then
      return true
    end
  end
  return false
end

local function matches_exclude(exclude_set, slug, title)
  if not exclude_set then
    return false
  end
  return exclude_set[slug:lower()] or exclude_set[title:lower()]
end

function M.discover(filter)
  local include = filter and filter.include
  if include and #include == 0 then
    include = nil
  end
  local exclude = build_exclude_set(filter and filter.exclude)
  local dirs = config.opts.search_dirs
  local seen = {}
  local docs = {}
  local scanned = 0
  local skipped_no_index = 0
  local skipped_filter = 0

  for _, dir in ipairs(dirs) do
    dir = utils.normalize_path(vim.fn.expand(dir))
    if vim.fn.isdirectory(dir) == 0 then
      notify("Doc dir not found: " .. dir, vim.log.levels.WARN)
    else
      local entries = vim.fn.glob(dir .. "/*", false, true)
      for _, path in ipairs(entries) do
        path = utils.normalize_path(path)
        local slug = vim.fn.fnamemodify(path, ":t")
        local index = path .. "/index.json"
        scanned = scanned + 1
        if vim.fn.isdirectory(path) == 1 and vim.fn.filereadable(index) == 1 and not seen[slug] then
          seen[slug] = true
          local info = M.find(slug) or {}
          local title = info.name or slug
          if matches_include(include, slug, title) and not matches_exclude(exclude, slug, title) then
            table.insert(docs, {
              slug = slug,
              name = slug,
              title = title,
              version = info.version or "",
              path = path,
              doc_dir = path,
            })
          else
            skipped_filter = skipped_filter + 1
          end
        else
          skipped_no_index = skipped_no_index + 1
        end
      end
    end
  end

  table.sort(docs, function(a, b)
    return (a.title or a.slug):lower() < (b.title or b.slug):lower()
  end)
  if scanned > 0 and #docs == 0 then
    notify(string.format("Scanned %d dir(s) but found 0 with index.json (skipped_no_index=%d, skipped_filter=%d)",
      scanned, skipped_no_index, skipped_filter), vim.log.levels.WARN)
  end
  return docs
end

return M
