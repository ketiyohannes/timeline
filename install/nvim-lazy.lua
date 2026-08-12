return {
  dir = "/Users/ketiyohannes/Documents/development/personal/diff-display",
  name = "codex-timeline",
  lazy = false,
  config = function()
    require("codex_timeline").setup({
      annotate_on_buf_enter = true,
      virtual_text = false,
    })
  end,
}
