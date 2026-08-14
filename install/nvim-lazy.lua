return {
  "ketiyohannes/timeline",
  name = "timeline",
  lazy = false,
  config = function()
    require("timeline").setup({
      annotate_on_buf_enter = true,
      virtual_text = false,
    })
  end,
}
