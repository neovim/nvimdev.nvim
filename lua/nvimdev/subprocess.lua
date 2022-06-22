local uv = vim.loop

local M = {}

function M.subprocess(opts, on_exit)
  if opts.stdout == nil then
    opts.stdout = uv.new_pipe(false)
  end

  if opts.stderr == nil then
    opts.stderr = uv.new_pipe(false)
  end

  local stdin

  if opts.input then
    stdin = uv.new_pipe(false)
  end

  local stdout_data = ''
  local stderr_data = ''

  local handle, err = uv.spawn(opts.command, {
    args = opts.args,
    cwd = opts.cwd,
    stdio = { stdin, opts.stdout or nil, opts.stderr  or nil},
  },
    function(code)
      if opts.stdout then opts.stdout:read_stop() end
      if opts.stderr then opts.stderr:read_stop() end

      if opts.stdout and not opts.stdout:is_closing() then opts.stdout:close() end
      if opts.stderr and not opts.stderr:is_closing() then opts.stderr:close() end
      if stdin       and not       stdin:is_closing()  then stdin:close() end

      on_exit(code, stdout_data, stderr_data)
    end
  )

  if not handle then
    if opts.stdout and not opts.stdout:is_closing() then opts.stdout:close() end
    if opts.stderr and not opts.stderr:is_closing() then opts.stderr:close() end
    if stdin  and not stdin:is_closing()  then stdin:close() end
    opts.input = nil
    error('Failed to spawn process '..err..'\n'..vim.inspect(opts))
  end

  if opts.stdout then
    opts.stdout:read_start(function(_, data)
      if data then
        stdout_data = stdout_data..data
      end
    end)
  end

  if opts.stderr then
    opts.stderr:read_start(function(_, data)
      if data then
        stderr_data = stderr_data..data
      end
    end)
  end

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
