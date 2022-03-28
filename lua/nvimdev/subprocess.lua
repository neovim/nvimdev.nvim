local uv = vim.loop

local M = {}

function M.subprocess(opts, on_exit)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local stdin

  if opts.input then
    stdin = uv.new_pipe(false)
  end

  local stdout_data = ''
  local stderr_data = ''

  local handle, err = uv.spawn(opts.command, {
    args = opts.args,
    cwd = opts.cwd,
    stdio = { stdin, stdout, stderr },
  },
    function(code)
      if stdout then stdout:read_stop() end
      if stderr then stderr:read_stop() end

      if stdout and not stdout:is_closing() then stdout:close() end
      if stderr and not stderr:is_closing() then stderr:close() end
      if stdin  and not stdin:is_closing()  then stdin:close() end

      on_exit(code, stdout_data, stderr_data)
    end
  )

  if not handle then
    if stdout and not stdout:is_closing() then stdout:close() end
    if stderr and not stderr:is_closing() then stderr:close() end
    if stdin  and not stdin:is_closing()  then stdin:close() end
    opts.input = nil
    error('Failed to spawn process '..err..'\n'..vim.inspect(opts))
  end

  stdout:read_start(function(_, data)
    if data then
      stdout_data = stdout_data..data
    end
  end)

  stderr:read_start(function(_, data)
    if data then
      stderr_data = stderr_data..data
    end
  end)

  if opts.input then
    stdin:write(opts.input)
    stdin:shutdown(function()
      if stdin then
        stdin:close()
      end
    end)
  end

end

return M
