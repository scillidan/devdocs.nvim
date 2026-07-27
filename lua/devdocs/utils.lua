local M = {}

function M.normalize_path(p)
  return (p:gsub("\\", "/"))
end

function M.exists(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.schedule(function()
    vim.notify("[devdocs] " .. msg, level)
  end)
  vim.api.nvim_echo({ { "[devdocs] " .. msg } }, false, {})
end

function M.mkdir(dir)
  local ok = vim.fn.mkdir(dir, "p")
  if ok ~= 1 and vim.in_fast_event() then
    vim.schedule(function()
      vim.fn.mkdir(dir, "p")
    end)
    return true
  end
  return ok == 1
end

function M.read_json(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if ok then
    return decoded
  end
  return nil
end

function M.write_json(path, data)
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    return false
  end
  local f = io.open(path, "w")
  if not f then
    return false
  end
  f:write(encoded)
  f:close()
  return true
end

return M
