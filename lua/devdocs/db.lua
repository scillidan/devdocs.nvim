local M = {}
local utils = require("devdocs.utils")

function M.load_entries(doc)
  local index_file = doc.doc_dir .. "/index.json"
  if vim.fn.filereadable(index_file) == 0 then
    return {}
  end

  local data = utils.read_json(index_file)
  if type(data) ~= "table" or type(data.entries) ~= "table" then
    return {}
  end

  local entries = {}
  for _, e in ipairs(data.entries) do
    table.insert(entries, {
      name = e.name,
      type = e.type,
      path = e.path,
      docset = doc,
    })
  end

  table.sort(entries, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

return M
