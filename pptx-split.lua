-- Quarto/pandoc filter for the pptx format only.
-- Pandoc's pptx writer does not shrink or paginate content, so this filter
--   * splits long tables across slides (header repeated),
--   * starts a new, titled "(cont.)" slide when text, tables or figures would
--     overflow or would otherwise land on an untitled slide,
--   * unwraps styling-only divs (keypoint, pearl, source, ...).
-- Budgets are rough estimates for a 10 x 5.6 in slide with the custom reference doc.

local TEXT_BUDGET = 1100       -- characters of body text per slide
local TABLE_BUDGET_PT = 280
local LINE_PT = 11             -- 9 pt text, line height
local ROW_PAD_PT = 14
local CHARS_PER_INCH = 11
local TABLE_WIDTH_IN = 8.6

local stringify = pandoc.utils.stringify

local function is_columns(b)
  return b.t == "Div" and b.classes:includes("columns")
end

local function is_callout(b)
  if b.t ~= "Div" then return false end
  for _, c in ipairs(b.classes) do
    if c:match("^callout") then return true end
  end
  return false
end

local function has_image(b)
  local found = false
  b:walk({ Image = function() found = true end })
  return found
end

local function contains_table(b)
  local found = false
  b:walk({ Table = function() found = true end })
  return found
end

local function unwrap_columns(b)
  local out = pandoc.List()
  for _, col in ipairs(b.content) do
    if col.t == "Div" then out:extend(col.content) else out:insert(col) end
  end
  return out
end

-- Replace styling divs by their contents; keep columns and callouts intact.
local function flatten(blocks)
  local out = pandoc.List()
  for _, b in ipairs(blocks) do
    if b.t == "Div" and not is_columns(b) and not is_callout(b) then
      out:extend(flatten(b.content))
    elseif b.t == "RawBlock" and b.format:match("html") then
      -- drop <br> and other html-only blocks
    elseif (b.t == "Para" or b.t == "Plain") and stringify(b):match("^%s*$") and not has_image(b) then
      -- drop empty paragraphs (e.g. a lone <br>)
    else
      out:insert(b)
    end
  end
  return out
end

local function is_media(b)
  if b.t == "Figure" then return true end
  if (b.t == "Para" or b.t == "Plain") and #b.content == 1 and b.content[1].t == "Image" then
    return true
  end
  return false
end

local function text_cost(b)
  return #stringify(b)
end

local function row_weight(row, widths)
  local lines = 1
  for j, cell in ipairs(row.cells) do
    local chars = #stringify(cell.contents)
    local cpl = math.max(5, math.floor(((widths[j] or 1) * TABLE_WIDTH_IN - 0.2) * CHARS_PER_INCH))
    local l = math.ceil(chars / cpl)
    if l > lines then lines = l end
  end
  return lines * LINE_PT + ROW_PAD_PT
end

local function split_table(tbl)
  local ncol = #tbl.colspecs
  local widths = {}
  local known = 0
  for j, spec in ipairs(tbl.colspecs) do
    local w = spec[2]
    if type(w) == "number" then widths[j] = w; known = known + w end
  end
  if known == 0 then
    for j = 1, ncol do widths[j] = 1 / ncol end
  end

  local head_w = 0
  for _, r in ipairs(tbl.head.rows) do head_w = head_w + row_weight(r, widths) end

  local rows = {}
  for _, body in ipairs(tbl.bodies) do
    for _, r in ipairs(body.body) do rows[#rows + 1] = r end
  end

  local chunks, cur, cur_w = {}, {}, head_w
  for _, r in ipairs(rows) do
    local w = row_weight(r, widths)
    if #cur > 0 and cur_w + w > TABLE_BUDGET_PT then
      chunks[#chunks + 1] = cur
      cur, cur_w = {}, head_w
    end
    cur[#cur + 1] = r
    cur_w = cur_w + w
  end
  if #cur > 0 then chunks[#chunks + 1] = cur end

  local out = {}
  for _, chunk in ipairs(chunks) do
    local t = tbl:clone()
    t.bodies = { { attr = pandoc.Attr(), row_head_columns = 0, head = {}, body = chunk } }
    out[#out + 1] = t
  end
  return out
end

local function split_list(b, budget)
  -- Split BulletList / OrderedList into groups of items under the budget.
  local groups, cur, cur_c = {}, {}, 0
  for _, item in ipairs(b.content) do
    local c = #stringify(pandoc.Div(item))
    if #cur > 0 and cur_c + c > budget then
      groups[#groups + 1] = cur
      cur, cur_c = {}, 0
    end
    cur[#cur + 1] = item
    cur_c = cur_c + c
  end
  if #cur > 0 then groups[#groups + 1] = cur end
  local out = {}
  local start = (b.t == "OrderedList") and b.start or 1
  for _, g in ipairs(groups) do
    if b.t == "BulletList" then
      out[#out + 1] = pandoc.BulletList(g)
    elseif start == 1 then
      out[#out + 1] = pandoc.OrderedList(g, pandoc.ListAttributes(1, b.style, b.delimiter))
      start = start + #g
    else
      -- pandoc's pptx writer gives every item of a continued list the same start
      -- number, so number the continuation items by hand.
      local paras = {}
      for _, item in ipairs(g) do
        local first = item[1]
        local inl = pandoc.Inlines({ pandoc.Str(tostring(start) .. ".") , pandoc.Space() })
        if first and (first.t == "Plain" or first.t == "Para") then
          inl:extend(first.content)
        end
        paras[#paras + 1] = pandoc.Para(inl)
        start = start + 1
      end
      out[#out + 1] = pandoc.Div(paras)
    end
  end
  return out
end

function Pandoc(doc)
  local blocks = flatten(doc.blocks)
  -- Columns that hold a table or too much text are unwrapped into a single flow.
  local flowed = pandoc.List()
  for _, b in ipairs(blocks) do
    if is_columns(b) and (contains_table(b) or #stringify(b) > TEXT_BUDGET * 1.1) then
      flowed:extend(flatten(unwrap_columns(b)))
    else
      flowed:insert(b)
    end
  end
  blocks = flowed
  local out = pandoc.List()
  local title = nil
  local cost, has_media, need_new = 0, false, false

  local function new_slide()
    if title then
      local inl = pandoc.Inlines(title)
      if stringify(inl):match("%(cont%.%)$") then
        out:insert(pandoc.Header(2, inl))
      else
        inl:insert(pandoc.Space())
        inl:insert(pandoc.Str("(cont.)"))
        out:insert(pandoc.Header(2, inl))
      end
    end
    cost, has_media, need_new = 0, false, false
  end

  for _, b in ipairs(blocks) do
    if b.t == "Header" and b.level <= 2 then
      out:insert(b)
      if b.level == 2 then title = b.content end
      cost, has_media, need_new = 0, false, false
    elseif b.t == "Table" then
      if cost > 0 or has_media or need_new then new_slide() end
      local parts = split_table(b)
      for i, t in ipairs(parts) do
        if i > 1 then new_slide() end
        out:insert(t)
      end
      need_new = true
      cost = 1
    elseif is_media(b) then
      if cost > 450 or has_media or need_new then new_slide() end
      out:insert(b)
      has_media = true
      need_new = true
    elseif b.t == "BulletList" or b.t == "OrderedList" then
      local c = text_cost(b)
      if need_new or (cost > 0 and cost + c > TEXT_BUDGET) then new_slide() end
      if c > TEXT_BUDGET then
        for i, part in ipairs(split_list(b, TEXT_BUDGET - cost)) do
          if i > 1 then new_slide() end
          out:insert(part)
          cost = cost + text_cost(part)
        end
      else
        out:insert(b)
        cost = cost + c
      end
    elseif b.t == "Header" then
      -- level >= 3 headings inside a slide
      out:insert(b)
      cost = cost + text_cost(b)
    else
      local c = text_cost(b)
      if c > 0 then
        if need_new or (cost > 0 and cost + c > TEXT_BUDGET) then new_slide() end
        cost = cost + c
      end
      out:insert(b)
    end
  end

  doc.blocks = out
  return doc
end
