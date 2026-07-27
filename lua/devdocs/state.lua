local M = {}
local config = require("devdocs.config")
local utils = require("devdocs.utils")

local _state = nil

local function load()
  if _state then
    return _state
  end
  local data = utils.read_json(config.state_file())
  _state = data or {
    metadata = { downloaded = 0 },
    docs = {},
  }
  _state.docs = _state.docs or {}
  _state.metadata = _state.metadata or { downloaded = 0 }
  return _state
end

local function save()
  utils.write_json(config.state_file(), load())
end

function M.get(key)
  return load().docs[key]
end

function M.set(key, value)
  load().docs[key] = vim.tbl_deep_extend("force", load().docs[key] or {}, value)
  save()
end

function M.remove(key)
  load().docs[key] = nil
  save()
end

function M.installed()
  local docs = {}
  for slug, status in pairs(load().docs) do
    if status.installed then
      table.insert(docs, slug)
    end
  end
  table.sort(docs)
  return docs
end

function M.metadata_downloaded(time)
  if type(time) == "number" then
    load().metadata.downloaded = time
    save()
  end
  local d = load().metadata.downloaded
  return type(d) == "number" and d or 0
end

function M.is_stale()
  local ttl = config.opts.metadata_ttl_days
  if ttl <= 0 then
    return true
  end
  local d = load().metadata.downloaded
  local downloaded = type(d) == "number" and d or 0
  return (os.time() - downloaded) > (ttl * 86400)
end

function M.clear()
  _state = nil
end

return M
