local M = {}

local filter = require("devdocs.filter")

function M.open(entries, opts)
  opts = opts or {}
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    require("devdocs.utils").notify("telescope not found", vim.log.levels.ERROR)
    return
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local cfg = require("devdocs.config").opts
  local docsets = opts.docsets or {}
  local query = opts.query or ""

  local filters = opts.filters or { docsets = {}, types = {} }
  local content_query = query
  if not opts.filters then
    local docset_ids, types, content = filter.parse_filter(query, docsets, entries)
    if docset_ids then
      filters.docsets = docset_ids
      filters.types = types or {}
      content_query = content or ""
    end
  end

  local shown = filter.filter_entries(entries, filters)

  local last_prompt = nil
  local cached_results = nil
  local function dynamic_fn(prompt)
    if prompt == last_prompt and cached_results then
      return cached_results
    end
    local docset_ids, types, content = filter.parse_filter(prompt, docsets, entries)
    local f
    if docset_ids then
      f = { docsets = docset_ids, types = types or {} }
    else
      f = { docsets = filters.docsets, types = filters.types }
    end
    local result = filter.filter_entries(entries, f)
    last_prompt = prompt
    cached_results = result
    return result
  end

  local sorters = require("telescope.sorters")
  local fzy = require("telescope.algos.fzy")
  local OFFSET = -fzy.get_score_floor()

  local function word_match(query, line)
    local line_lower = line:lower()
    for word in query:gmatch("%S+") do
      if not line_lower:find(word:lower(), 1, true) then
        return false
      end
    end
    return true
  end

  local function content_sorter()
    return sorters.Sorter:new({
      discard = true,
      scoring_function = function(_, prompt, line)
        local _, _, content = filter.parse_filter(prompt, docsets, entries)
        local query_text = content or prompt
        if query_text == "" then
          return 1
        end
        if not word_match(query_text, line) then
          return -1
        end
        local idx = line:lower():find(query_text:lower(), 1, true)
        if idx then
          return idx / (#line + 1)
        end
        return 1 / (#line + 1)
      end,
      highlighter = function(_, prompt, display)
        local _, _, content = filter.parse_filter(prompt, docsets, entries)
        local query_text = content or prompt
        if query_text == "" then
          return {}
        end
        local highlights = {}
        local display_lower = display:lower()
        for word in query_text:gmatch("%S+") do
          local start = 1
          while true do
            local s, e = display_lower:find(word:lower(), start, true)
            if not s then
              break
            end
            table.insert(highlights, { start = s, finish = e })
            start = e + 1
          end
        end
        return highlights
      end,
    })
  end

  local hl = cfg.highlights or {}
  local type_hl = hl.entry_type or "Comment"
  local docset_hl = hl.entry_docset or "Comment"

  local type_lens = {}
  local docset_lens = {}
  for _, e in ipairs(entries) do
    table.insert(type_lens, vim.fn.strdisplaywidth("[" .. e.type .. "]"))
    table.insert(docset_lens, vim.fn.strdisplaywidth(e.docset.title or e.docset.name))
  end
  table.sort(type_lens)
  table.sort(docset_lens)
  local function mid(t)
    if #t == 0 then return 0 end
    return t[math.ceil(#t / 2)]
  end
  local type_width = math.max(6, math.min(mid(type_lens), 16))
  local docset_width = math.max(8, math.min(mid(docset_lens), 22))

  local displayer = entry_display.create({
    separator = "  ",
    items = {
      { width = 35 },
      { width = type_width },
      { remaining = true },
    },
  })

  local function trunc(str, w)
    if vim.fn.strdisplaywidth(str) > w then
      return str:sub(1, math.max(1, w - 1)) .. "…"
    end
    return str
  end

  local function make_display(entry)
    return displayer({
      entry.name,
      { trunc("[" .. entry.type .. "]", type_width), type_hl },
      { trunc(entry.docset.title or entry.docset.name, docset_width), docset_hl },
    })
  end

  local function reopen()
    M.open(entries, {
      prompt = opts.prompt,
      query = content_query,
      filters = filters,
      docsets = docsets,
      on_select = opts.on_select,
    })
  end

  pickers
    .new({ debounce = 100 }, {
      prompt_title = filter.build_header("C-f filter | C-r reset", filters, #shown),
      default_text = query,
      finder = finders.new_dynamic({
        fn = dynamic_fn,
        entry_maker = function(entry)
          return {
            value = entry,
            ordinal = entry.name,
            display = make_display(entry),
          }
        end,
      }),
      sorter = content_sorter(),
      previewer = require("telescope.previewers").new_buffer_previewer({
        title = "Preview",
        dyn_title = function(_, entry)
          return entry.value.name
        end,
        define_preview = function(self, entry)
          local preview = require("devdocs.browser").preview_text(entry.value)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(preview, "\n", { plain = true }))
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local selections = picker:get_multi_selection()
          local selected_entries = {}
          if #selections > 0 then
            for _, sel in ipairs(selections) do
              table.insert(selected_entries, sel.value)
            end
          else
            local selection = action_state.get_selected_entry()
            if selection then
              table.insert(selected_entries, selection.value)
            end
          end
          actions.close(prompt_bufnr)
          if #selected_entries > 0 and opts.on_select then
            opts.on_select(selected_entries)
          end
        end)

        map("i", "<C-f>", function()
          local query_text = action_state.get_current_line()
          local docset_ids, types, content = filter.parse_filter(query_text, docsets, entries)
          if docset_ids then
            filters.docsets = docset_ids
            filters.types = types or {}
            content_query = content or ""
            actions.close(prompt_bufnr)
            reopen()
          else
            require("devdocs.utils").notify("No valid filter in query", vim.log.levels.WARN)
          end
        end)

        map("i", "<C-r>", function()
          filters = { docsets = {}, types = {} }
          content_query = ""
          actions.close(prompt_bufnr)
          reopen()
        end)

        map("i", "<C-q>", function()
          actions.close(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

function M.select(items, opts)
  opts = opts or {}
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values

  pickers.new({}, {
    prompt_title = opts.prompt or "Select",
    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        return {
          value = item,
          display = item.label,
          ordinal = item.label,
        }
      end,
    }),
    sorter = conf.generic_sorter or conf.file_sorter,
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and opts.on_select then
          opts.on_select(selection.value)
        end
      end)
      return true
    end,
  }):find()
end

return M
