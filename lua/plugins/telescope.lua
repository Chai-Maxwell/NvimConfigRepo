-- telescope.nvim 配置
-- 项目切换插件: telescope-project.nvim
--
-- 调用方式:
--   :Telescope project          (命令行)
--   或通过 alpha-life 启动页按 p
--
-- 项目数据存储在:
--   ~/.local/share/nvim/telescope-projects.txt
--   ~/.local/share/nvim/telescope-workspaces.txt

return {
  {
    "nvim-telescope/telescope.nvim",
    keys = {
      {
        "<leader>be",
        function()
          local actions = require("telescope.actions")
          require("telescope.builtin").buffers({
            -- 仅在 buffers picker 内关闭选中 buffer：
            -- 插入模式 <c-d> / 正常模式 dd
            -- 用 attach_mappings 注入，不影响其他 picker 的 <c-d> 预览滚动
            attach_mappings = function(_, map)
              map("i", "<c-d>", actions.delete_buffer)
              map("n", "dd", actions.delete_buffer)
              return true
            end,
          })
        end,
        desc = "Buffers",
      },
      { "<leader>ge", function() require("telescope.builtin").git_status() end, desc = "Git Status" },
      { "<leader>,", false },  -- 屏蔽 LazyVim 默认的 buffers 键位
      { "<leader>gs", false }, -- 屏蔽 LazyVim 默认的 git_status，已有 Fugitive
    },
    opts = {
      extensions = {
        -- telescope-project.nvim 的扩展配置
        -- 这些配置会被传递给扩展的 setup() 函数
        project = {
          -- 扫描这些目录下的子目录作为可选项目
          base_dirs = {
            "~/stuff",
          },
          -- 是否在项目中显示隐藏文件（dotfiles）
          hidden_files = false,
          -- 项目列表排序方式:
          --   "recent" - 按最近访问时间排序（默认）
          --   "asc"    - 按项目名字母升序
          --   "desc"   - 按项目名字母降序
          order_by = "recent",
          -- 搜索时匹配的字段:
          --   "title"             - 只匹配项目名
          --   "path"              - 只匹配路径
          --   {"title", "path"}   - 同时匹配项目名和路径
          search_by = "title",
          -- 注意: display_type 和 hide_workspace 不在此处配置
          -- 因为 setup() 不支持这两个参数，见下方 wrapper 说明
        },
      },
    },
  },
  {
    "nvim-telescope/telescope-project.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    config = function()
      -- 加载 telescope 扩展
      require("telescope").load_extension("project")

      -- ============================================================
      -- Wrapper: 注入 display_type / hide_workspace 默认值
      -- ============================================================
      --
      -- 为什么需要这个 wrapper？
      --
      -- telescope-project.nvim 的 setup() 函数（main.lua:52-78）
      -- 只保存了以下配置项：
      --   base_dirs, hidden_files, order_by, on_project_selected,
      --   search_by, sync_with_nvim_tree, cd_scope, mappings, theme
      --
      -- display_type 和 hide_workspace 不在其中！
      -- 这两个参数只在 M.project(opts) 中从 opts 参数读取
      -- （finders.lua:11-12）。
      --
      -- 当执行 :Telescope project 时，命令解析器传递空 opts = {}，
      -- 所以这两项永远是 nil → 退化为默认行为（minimal + 显示 w0）。
      --
      -- 因此必须通过包装 project() 函数，在每次调用前注入默认值。
      --
      -- display_type 可选值:
      --   "minimal"     - 只显示项目名（默认）
      --   "full"        - 显示 项目名 [完整路径]
      --   "two-segment" - 显示 项目名 [最后两级目录]
      --
      -- hide_workspace = true 时隐藏项目名后面的 w0/w1 工作区标识，
      -- 关于 w0: 每个项目被分配到一个工作区 (workspace)，
      -- 默认是 w0，可通过多工作区分类组织项目。
      -- ============================================================

      local ext = require("telescope").extensions.project
      local orig_project = ext.project

      ext.project = function(opts)
        -- vim.tbl_deep_extend("force", defaults, user_opts)
        -- "force" 模式: defaults 中的值覆盖 user_opts 中的同名 key
        -- 同时 user_opts 中独有的 key 也会保留
        -- 这里作为左操作数，确保 display_type/hide_workspace 始终有默认值
        opts = vim.tbl_deep_extend("force", {
          display_type = "two-segment", -- 显示完整路径而非仅项目名
          hide_workspace = true, -- 隐藏 w0/w1 等工作区标识
        }, opts or {})
        return orig_project(opts)
      end
    end,
  },
}
