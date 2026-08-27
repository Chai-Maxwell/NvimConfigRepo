-- ~/.config/nvim/lua/plugins/markdown-preview.lua

-- ===== 按 buffer 切换预览 =====
--
-- 插件自带的 toggle_preview() 在“关闭”分支调用 stop_preview()，
-- 而 stop_preview() 会 stop_server()（close_all_pages），
-- 把【所有】文件的预览页面都关掉。这里改为只关闭当前 buffer 的预览页，
-- 这样打开第二个 .md 的预览不会影响前一个 .md 的预览。
local function toggle_preview()
  if vim.b.MarkdownPreviewToggleBool == 1 then
    vim.fn["mkdp#rpc#preview_close"]() -- 只向服务器发送当前 buffer 的 close_page
  else
    vim.fn["mkdp#util#open_preview_page"]()
    vim.b.MarkdownPreviewToggleBool = 1
  end
end

return {
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },

    -- ===== 禁用 markdown-it-emoji 渲染 =====
    -- 插件无此配置开关（pages/index.jsx 中 .use(emoji) 硬编码），
    -- 需改编译产物 app/out/_next/static/*/pages/index.js：把 emoji 规则的
    -- scanRE/replaceRE 换成永不匹配的正则 /[^\s\S]/g。
    -- build 函数在插件安装/更新后自动执行，保证补丁不丢失；
    -- 也可手动 :Lazy build markdown-preview.nvim 重打。
    build = function(plugin)
      local chunks = vim.fn.glob(plugin.dir .. "/app/out/_next/static/*/pages/index.js", false, true)
      local patched = false
      for _, f in ipairs(chunks) do
        local fp = assert(io.open(f, "rb"))
        local content = fp:read("*a")
        fp:close()
        local new = content:gsub(
          "[%a_$][%w_$]*%.scanRE,[%a_$][%w_$]*%.replaceRE",
          "/[^\\s\\S]/g,/[^\\s\\S]/g",
          1
        )
        if new ~= content then
          local out = assert(io.open(f, "wb"))
          out:write(new)
          out:close()
          patched = true
        end
      end
      if not patched then
        vim.notify(
          "[markdown-preview.nvim] emoji 禁用补丁未匹配到目标，插件结构可能已变化，需手动检查",
          vim.log.levels.WARN
        )
      end
    end,

    -- 覆盖 LazyVim markdown extra 中的 <leader>cp（原本指向 MarkdownPreviewToggle）
    keys = {
      {
        "<leader>cp",
        ft = "markdown",
        toggle_preview,
        desc = "Markdown Preview",
      },
    },

    config = function()
      -- ===== 关键设置 =====
      vim.g.mkdp_auto_close = 0 -- 切换 buffer 时不关闭浏览器预览
      vim.g.mkdp_refresh_slow = 0 -- 保存文件时自动刷新预览
      vim.g.mkdp_auto_start = 0 -- 打开 .md 时不自动启动预览（按需手动 :MarkdownPreview）

      -- 关闭 .md 文档滚动与浏览器预览同步
      -- mkit 会合并覆盖 markdown-it 默认选项(见插件 app/pages/index.jsx)：
      -- 关闭 typographer，即 (c)→©、(r)→®、--→–、...→…、直引号→弯引号 全部不替换。
      vim.g.mkdp_preview_options = {
        disable_sync_scroll = 1,
        mkit = { typographer = false },
      }

      -- ===== 预览页在 niri 当前列新开浏览器窗口 =====
      --
      -- 默认行为：server 用 xdg-open 打开 URL → firefox 复用已有实例，
      -- 在其他 row 的 firefox 里开新标签页，并把 niri 焦点拉过去。
      -- 这里改为强制 --new-window：firefox 新建窗口 → niri 在当前聚焦列
      -- 新增一行（即当前 row 区域），不再跳转到其他 row。
      --
      -- 【原理】server.js 读取 g:mkdp_browserfunc，非空时
      --   plugin.nvim.call(browserfunc, [url]) 由本函数负责打开，
      --   绕过 opener 的 xdg-open 路径。
      vim.g.mkdp_browserfunc = "MkdpOpenBrowserNewWindow"
      vim.cmd([[
        function! MkdpOpenBrowserNewWindow(url) abort
          if executable('firefox')
            " detach: 不随 nvim 退出而关闭；CLI 立即返回，不阻塞 nvim
            call jobstart(['firefox', '--new-window', a:url], {'detach': v:true})
          else
            " firefox 缺失时回退到系统默认处理
            call system('xdg-open ' . shellescape(a:url) . ' &')
          endif
        endfunction
      ]])

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

      -- ===== 重写 buffer 局部命令 MarkdownPreviewToggle =====
      -- 插件的 s:init_command() 会在 BufEnter/FileType 时重新定义该命令，
      -- 这里挂在同样的事件上（注册更晚，执行顺序在插件之后，覆盖其定义）。
      local toggle_group = vim.api.nvim_create_augroup("UserMarkdownPreviewToggle", { clear = true })
      vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
        group = toggle_group,
        callback = function()
          if vim.bo.filetype ~= "markdown" then
            return
          end
          vim.api.nvim_buf_create_user_command(0, "MarkdownPreviewToggle", toggle_preview, { force = true })
        end,
      })

      -- LazyVim 原 config 中的 do FileType：插件懒加载后，为当前 buffer 补建
      -- buffer 局部命令（自定义 config 覆盖 LazyVim 的 config 后需手动补上）
      vim.cmd([[do FileType]])
    end,
  },
}
