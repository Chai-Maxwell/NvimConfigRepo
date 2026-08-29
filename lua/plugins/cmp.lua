-- ~/.config/nvim/lua/plugins/cmp.lua
-- 释放 <C-Space> 给输入法切换（fcitx5 等）
return {
  {
    "hrsh7th/nvim-cmp",
    opts = function(_, opts)
      -- 移除 LazyVim 默认的 <C-Space> 补全触发，避免覆盖输入法切换快捷键
      opts.mapping["<C-Space>"] = nil
    end,
  },
}
