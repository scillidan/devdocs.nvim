local M = {}

local function check(command)
  if vim.fn.executable(command) == 0 then
    vim.health.error(command .. " not found")
  else
    vim.health.ok(command .. " found")
  end
end

M.check = function()
  vim.health.start("devdocs.nvim tools check")
  check("curl")
  check("tar")

  local cfg = require("devdocs.config")
  vim.health.start("devdocs.nvim directories")
  vim.health.info("Data dir: " .. cfg.data_dir())
  vim.health.info("Docs dir: " .. cfg.docs_dir())
end

return M
