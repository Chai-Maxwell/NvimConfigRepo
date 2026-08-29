-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
-- lua/config/autocmds.lua
-- lua/config/autocmds.lua

-- .md 文件快捷语法替换（仅在 :w 时光标前后 4 行内执行，避免大文件卡顿）
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.md",
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local crow = cursor[1] -- 1-indexed cursor row

    -- 仅处理光标前后 4 行（API 使用 0-indexed）
    local total_lines = vim.api.nvim_buf_line_count(bufnr)
    local start_line = math.max(0, crow - 5)
    local end_line = math.min(total_lines, crow + 4)

    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
    if #lines == 0 then
      return
    end

    local text = table.concat(lines, "\n")

    -- ============================================================
    -- 提前退出：如果范围内不含任何快捷语法，跳过处理
    -- ============================================================
    local has_figure = text:find("figure%[")
    local has_katex_macros = text:find("\\Var")
      or text:find("\\Cov")
      or text:find("\\diag")
      or text:find("\\upd")
      or text:find("\\upg")
      or text:find("\\upe")
      or text:find("\\upi")
      or text:find("\\leftBrace")
      or text:find("\\rightEnd")
      or text:find("\\par")
      or text:find("\\part%s*{")
      or text:find("\\deri")
      or text:find("\\dbm")
      or text:find("\\ddbm")
      or text:find("\\partSec%s*{")
      or text:find("\\delt%s*{")

    if not has_figure and not has_katex_macros then
      return
    end

    -- ============================================================
    -- 从文件开头扫描到 start_line，判断是否在代码块内
    -- ============================================================
    local in_code_block = false
    if start_line > 0 then
      local pre_lines = vim.api.nvim_buf_get_lines(bufnr, 0, start_line, false)
      for _, l in ipairs(pre_lines) do
        if l:match("^```") then
          in_code_block = not in_code_block
        end
      end
    end

    -- ============================================================
    -- Step 1: figure[(path)(caption)[(size)]] → <figure> HTML
    --   在范围内文本上执行
    -- ============================================================
    local modified = false

    local function normalize_size(s)
      s = s:match("^%s*(.-)%s*$") -- trim
      if s == "" then
        return nil
      end
      s = s:gsub("%%$", "") -- strip %, re-add in format
      return s
    end

    if has_figure then
      -- 3-arg: figure[(path)(caption)(size)]
      local new_text, n3 = text:gsub("figure%[%(([^)]*)%)%(([^)]*)%)%(([^)]*)%)%]", function(path, caption, size)
        modified = true
        size = normalize_size(size)
        if size then
          return string.format(
            '<figure class="image-round" style="--image-width:%s%%">\n  <img src="%s">\n  <figcaption>%s</figcaption>\n</figure>',
            size,
            path,
            caption
          )
        else
          return string.format(
            '<figure class="image-round">\n  <img src="%s">\n  <figcaption>%s</figcaption>\n</figure>',
            path,
            caption
          )
        end
      end)
      if n3 > 0 then
        text = new_text
      end

      -- 2-arg: figure[(path)(caption)]
      local new_text2, n2 = text:gsub("figure%[%(([^)]*)%)%(([^)]*)%)%]", function(path, caption)
        modified = true
        return string.format(
          '<figure class="image-round">\n  <img src="%s">\n  <figcaption>%s</figcaption>\n</figure>',
          path,
          caption
        )
      end)
      if n2 > 0 then
        text = new_text2
      end
    end

    if modified then
      lines = vim.split(text, "\n", { plain = true })
    end

    -- ============================================================
    -- Step 2: KaTeX macro substitution (逐行处理范围内文本)
    -- ============================================================
    if not has_katex_macros then
      if modified then
        vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, lines)
      end
      return
    end

    local new_lines = {}

    for _, line in ipairs(lines) do
      local processed = line

      -- 检测代码块边界
      if processed:match("^```") then
        in_code_block = not in_code_block
        table.insert(new_lines, processed)
        goto continue
      end

      -- 跳过代码块内容
      if in_code_block then
        table.insert(new_lines, processed)
        goto continue
      end

      -- 跳过行内代码（简化处理：包含反引号对的行跳过）
      if not processed:match("`.*`") then
        -- 基础 KaTeX 宏
        processed = processed:gsub("\\Var", "\\operatorname{Var}")
        processed = processed:gsub("\\Cov", "\\operatorname{Cov}")
        processed = processed:gsub("\\diag", "\\operatorname{diag}")
        processed = processed:gsub("\\upd", "\\mathrm{d}")
        processed = processed:gsub("\\upg", "\\mathrm{g}")
        processed = processed:gsub("\\upe", "\\mathrm{e}")
        processed = processed:gsub("\\upi", "\\mathrm{i}")

        -- 多行宏
        processed = processed:gsub("\\leftBrace", "\\left\\{\\begin{aligned}")
        processed = processed:gsub("\\rightEnd", "\\end{aligned}\\right.")

        -- 复杂宏
        -- \\par 替换为 ¶：需同时匹配 "后跟非字母" 和 "行尾" 两种情况
        -- Lua pattern 不支持 | 交替，故拆为两次 gsub
        processed = processed:gsub("\\par(%A)", "¶%1")
        processed = processed:gsub("\\par$", "¶")
        processed = processed:gsub("\\part%s*{(.-)}%s*{(.-)}", "\\frac{\\partial %1}{\\partial %2}")
        processed = processed:gsub("\\deri%s*{(.-)}%s*{(.-)}", "\\frac{\\mathrm{d}%1}{\\mathrm{d}%2}")
        processed = processed:gsub("\\dbm%s*{(.-)}", "\\dot{\\bm{%1}}")
        processed = processed:gsub("\\ddbm%s*{(.-)}", "\\ddot{\\bm{%1}}")
        processed = processed:gsub("\\partSec%s*{(.-)}%s*{(.-)}%s*{(.-)}", "\\frac{\\partial^2 %1}{\\partial %2 \\partial %3}")
        processed = processed:gsub("\\delt%s*{(.-)}%s*{(.-)}", "\\frac{\\delta %1}{\\delta %2}")
      end

      if processed ~= line then
        modified = true
      end

      table.insert(new_lines, processed)
      ::continue::
    end

    -- 仅在内容改变时写入，避免无意义的 undo 历史
    if modified then
      vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, new_lines)
    end
  end,
})

-- 用系统文件管理器打开当前工作文件夹（macOS: Finder, Linux: xdg-open）
vim.api.nvim_create_user_command("OpenInFolder", function()
  local platform = require("config.platform")
  vim.fn.jobstart(platform.open_folder(vim.fn.getcwd()), { detach = true })
end, {})

-- 图片文件 → 交给系统默认查看器打开（与 neo-tree 中 PDF 的处理方式一致）
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.{png,jpg,jpeg,gif,bmp,webp,tiff,svg,heic,ico}",
  callback = function()
    local file = vim.fn.expand("%:p")
    if file == "" then
      return
    end
    -- 用系统默认应用打开图片
    local platform = require("config.platform")
    vim.fn.jobstart(platform.open_file(file), { detach = true })
    -- 关闭当前 buffer，切回上一个
    vim.cmd("bdelete")
  end,
})
