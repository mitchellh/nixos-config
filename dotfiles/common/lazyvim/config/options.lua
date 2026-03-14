-- Patch vim.api.nvim_cmd to silently skip :helptags for read-only nix store paths.
-- lazy.nvim calls: vim.api.nvim_cmd({ cmd = "helptags", args = { docs } }, { output = true })
-- which fails with E152 on /nix/store paths.
local orig_nvim_cmd = vim.api.nvim_cmd
vim.api.nvim_cmd = function(cmd, opts)
  if type(cmd) == "table" and cmd.cmd == "helptags" then
    local args = cmd.args or {}
    if type(args[1]) == "string" and args[1]:match("^/nix/store/") then
      return ""
    end
  end
  return orig_nvim_cmd(cmd, opts)
end
