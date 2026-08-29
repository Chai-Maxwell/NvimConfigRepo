-- ~/.config/nvim/lua/config/platform.lua
-- 平台检测与跨平台命令抽象层
-- 通过此模块统一处理 macOS 和 Linux 之间的命令差异

local M = {}

local sysname = vim.uv.os_uname().sysname
M.is_mac = sysname == "Darwin"
M.is_linux = sysname == "Linux"

---用系统默认应用打开文件
---@param path string 文件路径
---@return string[] 命令和参数列表，可直接传入 vim.fn.jobstart
function M.open_file(path)
  if M.is_mac then
    return { "open", path }
  else
    return { "xdg-open", path }
  end
end

---用文件管理器打开目录
---macOS: Finder, Linux: xdg-open（自动调用默认文件管理器）
---@param path string 目录路径
---@return string[] 命令和参数列表
function M.open_folder(path)
  if M.is_mac then
    return { "open", path }
  else
    return { "xdg-open", path }
  end
end

---将文件或目录移到回收站
---macOS: AppleScript Finder, Linux: KDE kioclient（与 Dolphin 共享回收站）
---@param path string 文件/目录路径
---@return string[] 命令和参数列表
function M.trash_cmd(path)
  if M.is_mac then
    return { "osascript", "-e", string.format('tell app "Finder" to delete POSIX file %q', path) }
  else
    return { "kioclient", "move", path, "trash:/" }
  end
end

---获取 latexindent 命令路径
---macOS 上优先使用 Homebrew 安装的版本（TeX Live 自带版缺少 Perl 依赖会崩溃），
---如果 Homebrew 路径不存在则回退到 PATH 中的 latexindent
---@return string latexindent 命令
function M.latexindent_cmd()
  if M.is_mac then
    -- Apple Silicon Homebrew
    if vim.uv.fs_stat("/opt/homebrew/bin/latexindent") then
      return "/opt/homebrew/bin/latexindent"
    end
    -- Intel Homebrew
    if vim.uv.fs_stat("/usr/local/bin/latexindent") then
      return "/usr/local/bin/latexindent"
    end
  end
  -- Linux 或 macOS 上 Homebrew 路径不存在的回退
  return "latexindent"
end

return M
