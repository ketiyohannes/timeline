local M = {}

local palettes = {
  dark = {
    add_bg = "#173A2A",
    add_fg = "#7EE787",
    delete_bg = "#45232B",
    delete_fg = "#FF7B92",
    change_bg = "#44391F",
    change_fg = "#FFD866",
    accent_bg = "#27365F",
    accent_fg = "#8AADF4",
    border = "#6E8CC7",
    title = "#C6D0F5",
  },
  light = {
    add_bg = "#D8F3DF",
    add_fg = "#16713A",
    delete_bg = "#FBE0E4",
    delete_fg = "#B4233C",
    change_bg = "#F9EDC7",
    change_fg = "#8A5A00",
    accent_bg = "#DDE7FA",
    accent_fg = "#2456A6",
    border = "#5373A8",
    title = "#23395D",
  },
}

function M.apply(overrides)
  local palette = vim.tbl_extend("force", palettes[vim.o.background] or palettes.dark, overrides or {})
  local set = vim.api.nvim_set_hl

  -- Full-line backgrounds keep syntax colors intact while making the patch
  -- unmistakable. Gutter signs and file rows use brighter foreground colors.
  set(0, "CodexTimelineAddLine", { bg = palette.add_bg, bold = true })
  set(0, "CodexTimelineDeleteLine", { bg = palette.delete_bg, bold = true })
  set(0, "CodexTimelineChangeLine", { bg = palette.change_bg, bold = true })
  set(0, "CodexTimelineAddSign", { fg = palette.add_fg, bg = palette.add_bg, bold = true })
  set(0, "CodexTimelineDeleteSign", { fg = palette.delete_fg, bg = palette.delete_bg, bold = true })
  set(0, "CodexTimelineAddFile", { fg = palette.add_fg, bg = palette.add_bg, bold = true })
  set(0, "CodexTimelineDeleteFile", { fg = palette.delete_fg, bg = palette.delete_bg, bold = true })
  set(0, "CodexTimelineChangeFile", { fg = palette.change_fg, bg = palette.change_bg, bold = true })
  set(0, "CodexTimelineChangeNumber", { fg = palette.accent_fg, bold = true })
  set(0, "CodexTimelineCursorLine", { bg = palette.accent_bg, bold = true })
  set(0, "CodexTimelineBorder", { fg = palette.border })
  set(0, "CodexTimelineTitle", { fg = palette.title, bold = true })
  set(0, "CodexTimelineFilePath", { fg = palette.accent_fg, bold = true })
  set(0, "CodexTimelineSign", { fg = palette.accent_fg, bold = true })
  set(0, "CodexTimelineVirtualText", { fg = palette.accent_fg, italic = true })
  set(0, "TimelineSearchMatch", { bg = palette.accent_bg, bold = true })
  set(0, "TimelineSearchCurrent", { fg = palette.accent_fg, bg = palette.accent_bg, bold = true, underline = true })
end

return M
