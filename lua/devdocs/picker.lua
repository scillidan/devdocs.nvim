local M = {}

function M.open(entries, opts)
  local cfg = require("devdocs.config").opts
  if cfg.picker == "telescope" then
    local ok, _ = pcall(require, "telescope")
    if not ok then
      require("devdocs.utils").notify("telescope not found", vim.log.levels.ERROR)
      return
    end
    local telescope_picker = require("devdocs.picker.telescope")
    local ok_t, t_err = pcall(telescope_picker.open, entries, opts)
    if not ok_t then
      require("devdocs.utils").notify("telescope picker failed: " .. tostring(t_err), vim.log.levels.ERROR)
    end
    return
  end
  if cfg.picker == "fzf" then
    local ok, _ = pcall(require, "fzf-lua")
    if not ok then
      require("devdocs.utils").notify("fzf-lua not found", vim.log.levels.ERROR)
      return
    end
    local fzf_picker = require("devdocs.picker.fzf")
    local ok_fzf, fzf_err = pcall(fzf_picker.open, entries, opts)
    if not ok_fzf then
      require("devdocs.utils").notify("fzf picker failed: " .. tostring(fzf_err), vim.log.levels.ERROR)
    end
    return
  end
  require("devdocs.utils").notify("Unsupported picker: " .. tostring(cfg.picker), vim.log.levels.ERROR)
end

function M.select(items, opts)
  local cfg = require("devdocs.config").opts
  if cfg.picker == "telescope" then
    local ok, _ = pcall(require, "telescope")
    if not ok then
      require("devdocs.utils").notify("telescope not found", vim.log.levels.ERROR)
      return
    end
    local telescope_picker = require("devdocs.picker.telescope")
    telescope_picker.select(items, opts)
    return
  end
  if cfg.picker == "fzf" then
    local ok, _ = pcall(require, "fzf-lua")
    if not ok then
      require("devdocs.utils").notify("fzf-lua not found", vim.log.levels.ERROR)
      return
    end
    local fzf_picker = require("devdocs.picker.fzf")
    fzf_picker.select(items, opts)
    return
  end
  require("devdocs.utils").notify("Unsupported picker: " .. tostring(cfg.picker), vim.log.levels.ERROR)
end

return M
