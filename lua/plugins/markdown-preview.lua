-- ~/.config/nvim/lua/plugins/markdown-preview.lua
return {
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },

    build = function()
      -- ===== 原始安装步骤 =====
      vim.fn["mkdp#util#install"]()

      local plugin_dir = vim.fn.stdpath("data") .. "/lazy/markdown-preview.nvim"
      local app_dir = plugin_dir .. "/app"
      local idx_file = app_dir .. "/pages/index.jsx"

      if vim.fn.filereadable(idx_file) ~= 1 then
        vim.notify("markdown-preview: 未找到 app/pages/index.jsx，补丁失败", vim.log.levels.ERROR)
        return
      end

      local content = table.concat(vim.fn.readfile(idx_file), "\n")

      -- 用源码特征判断各补丁是否已应用（避免插件更新后残留标记导致误判）
      local need_mark = not content:find("markdownItMark")      -- ==高亮== 语法补丁
      local need_no_emoji = content:find("import emoji") ~= nil -- 关闭 emoji 替换补丁

      if not need_mark and not need_no_emoji then
        return
      end

      if vim.fn.executable("node") ~= 1 or vim.fn.executable("npm") ~= 1 then
        vim.notify("markdown-preview: 需要 node/npm 才能打补丁，跳过", vim.log.levels.WARN)
        return
      end

      local output = ""

      -- ===== 补丁 1：注入 markdown-it-mark 支持 ==高亮== 语法 =====
      if need_mark then
        vim.notify("markdown-preview: 正在安装 markdown-it-mark 依赖 (仅首次，需要联网)...", vim.log.levels.INFO)

        output = vim.fn.system(
          "cd " .. vim.fn.shellescape(plugin_dir) .. " && npm install --production --legacy-peer-deps 2>&1"
        )
        if vim.v.shell_error ~= 0 then
          vim.notify("markdown-preview: npm install 失败\n" .. output, vim.log.levels.ERROR)
          return
        end

        output = vim.fn.system(
          "cd " .. vim.fn.shellescape(plugin_dir) .. " && npm install markdown-it-mark --no-save --legacy-peer-deps 2>&1"
        )
        if vim.v.shell_error ~= 0 then
          vim.notify("markdown-preview: markdown-it-mark 安装失败\n" .. output, vim.log.levels.ERROR)
          return
        end

        local import_ok = content:find("import markdown%-it%-deflist") ~= nil
        local use_ok = content:find("%.use%(markdownDeflist%)") ~= nil

        if import_ok and use_ok then
          content = content:gsub(
            "(import markdown%-it%-deflist[^\n]*\n)",
            "%1import markdownItMark from 'markdown-it-mark'\n",
            1
          )
          content = content:gsub("(%s*%.use%(markdownDeflist%))", "%1\n        .use(markdownItMark)", 1)
        else
          vim.notify("markdown-preview: index.jsx 结构不匹配，==高亮== 补丁失败", vim.log.levels.ERROR)
        end
      end

      -- ===== 补丁 2：关闭 emoji 替换（:smile: → 😄） =====
      if need_no_emoji then
        content = content:gsub("import emoji from 'markdown%-it%-emoji'\n", "")
        content = content:gsub("%s*%.use%(emoji%)\n", "")
      end

      vim.fn.writefile(vim.split(content, "\n"), idx_file)

      -- ===== 重新构建 Next.js 静态导出 =====
      -- NODE_OPTIONS: Node>=17 需要 openssl-legacy-provider 以兼容 Next.js 7 的 webpack
      local next_bin = plugin_dir .. "/node_modules/.bin/next"
      local build_cmd = "cd "
        .. vim.fn.shellescape(app_dir)
        .. " && rm -rf .next out"
        .. " && NODE_OPTIONS=--openssl-legacy-provider "
        .. next_bin
        .. " build 2>&1"
        .. " && NODE_OPTIONS=--openssl-legacy-provider "
        .. next_bin
        .. " export 2>&1"

      vim.notify("markdown-preview: 正在构建预览页面...", vim.log.levels.INFO)

      output = vim.fn.system(build_cmd)
      if vim.v.shell_error ~= 0 then
        vim.notify("markdown-preview: next build 失败\n" .. output, vim.log.levels.ERROR)
        return
      end

      vim.notify("markdown-preview: ✅ 补丁完成 (==高亮== 语法已支持，emoji/(c) 替换已关闭)", vim.log.levels.INFO)
    end,

    config = function()
      -- ===== 关键设置 =====
      vim.g.mkdp_auto_close = 0 -- 切换 buffer 时不关闭浏览器预览
      vim.g.mkdp_refresh_slow = 0 -- 保存文件时自动刷新预览
      vim.g.mkdp_auto_start = 0 -- 打开 .md 时不自动启动预览（按需手动 :MarkdownPreview）

      -- 关闭 .md 文档滚动与浏览器预览同步
      vim.g.mkdp_preview_options = {
        mkit = {
          -- 关闭 typographer 字符替换：(c)→©️、(r)→®️、"..."→…、智能引号等
          typographer = false,
        },
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
            local ftype = vim.fn.getftype(font_link)
            if ftype ~= "link" then
              vim.fn.system("ln -sf " .. vim.fn.shellescape(font_src) .. " " .. vim.fn.shellescape(font_link))
            end
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
