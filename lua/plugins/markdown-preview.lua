-- ~/.config/nvim/lua/plugins/markdown-preview.lua
return {
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },

    config = function()
      -- ===== 关键设置 =====
      vim.g.mkdp_auto_close = 0 -- 切换 buffer 时不关闭浏览器预览
      vim.g.mkdp_refresh_slow = 0 -- 保存文件时自动刷新预览
      vim.g.mkdp_auto_start = 0 -- 打开 .md 时不自动启动预览（按需手动 :MarkdownPreview）

      -- 关闭 .md 文档滚动与浏览器预览同步
      vim.g.mkdp_preview_options = {
        disable_sync_scroll = 1,
      }

      -- ===== 设置自定义 CSS 并绑定本地字体（断网也能用） =====
      --
      -- 【原理】
      -- markdown-preview.nvim 用本地 HTTP 服务器渲染预览，服务器将
      --   /_static/* 路径映射到 <plugin_dir>/app/_static/ 目录。
      -- style.css 中的 @import url("font/fz-kai-z-03.css") 在浏览器中
      --   解析为 /_static/font/fz-kai-z-03.css，由插件服务器提供。
      -- 这里用符号链接将项目 .config/font/ 映射到插件的 _static/font/，
      --   字体 CSS 和 WOFF2 分片全部走本地 localhost，零网络请求。
      --
      -- 符号链接放在 set_css() 中而非 build() 中，是为了在插件更新
      -- （_static/ 目录被替换）后，下次打开 Markdown 时自动重建。
      local function set_css()
        local cwd = vim.fn.getcwd()
        local css = cwd .. "/.config/style.css"

        if vim.fn.filereadable(css) == 1 then
          vim.g.mkdp_markdown_css = css

          -- 创建 /_static/font → <项目>/.config/font 符号链接
          local font_src = cwd .. "/.config/font"
          if vim.fn.isdirectory(font_src) == 1 then
            local plugin_static = vim.fn.stdpath("data") .. "/lazy/markdown-preview.nvim/app/_static"
            local font_link = plugin_static .. "/font"
            -- 始终强制更新符号链接，防止 cwd 改变后指向旧目录
            vim.fn.system("ln -sfn " .. vim.fn.shellescape(font_src) .. " " .. vim.fn.shellescape(font_link))
          end
        else
          vim.g.mkdp_markdown_css = ""
        end
      end

      -- 初始设置
      set_css()

      -- 进入 markdown 时更新
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "markdown",
        callback = set_css,
      })

      -- 切换工作目录时更新（可选但推荐）
      vim.api.nvim_create_autocmd("DirChanged", {
        callback = set_css,
      })
    end,
  },
}
