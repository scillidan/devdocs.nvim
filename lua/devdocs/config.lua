local M = {}

M.opts = {
  ensure_installed = {},
  search_dirs = {},
  browser = "",
  picker = "fzf",
  window = {
    mode = { "float", { width = 0.8, height = 0.85 } },
  },
  highlights = {
    tab = "TabLine",
    tab_active = "TabLineSel",
    entry_type = "Comment",
    entry_docset = "Comment",
  },
  preview_max_lines = 200,
  metadata_ttl_days = 7,
  download_retries = 3,
  download_timeout = 300,
  include_documents = nil,
  exclude_documents = nil,
}

function M.data_dir()
  return vim.fn.stdpath("data") .. "/devdocs"
end

function M.docs_dir()
  return M.data_dir() .. "/docs"
end

function M.metadata_file()
  return M.data_dir() .. "/metadata.json"
end

function M.state_file()
  return M.data_dir() .. "/state.json"
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  if type(M.opts.search_dirs) == "function" then
    M.opts.search_dirs = M.opts.search_dirs()
  end
end

return M
