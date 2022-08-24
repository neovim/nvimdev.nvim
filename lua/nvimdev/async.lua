---Executes a future with a callback when it is done
---@param func function: the future to execute
local function execute(func, ...)
  local thread = coroutine.create(func)

  local function step(...)
    local ret = {coroutine.resume(thread, ...)}
    local stat, err_or_fn, nargs = unpack(ret)

    if not stat then
      error(string.format("The coroutine failed with this message: %s\n%s",
        err_or_fn, debug.traceback(thread)))
    end

    if coroutine.status(thread) == 'dead' then
      return
    end

    local args = {select(4, unpack(ret))}
    args[nargs] = step
    err_or_fn(unpack(args, 1, nargs))
  end

  step(...)
end

local M = {}

---Creates an async function with a callback style function.
---@param func function: A callback style function to be converted. The last argument must be the callback.
---@param argc number: The number of arguments of func. Must be included.
---@return function: Returns an async function
function M.wrap(func, argc)
  return function(...)
    if not coroutine.running() or select('#', ...) == argc then
      return func(...)
    end
    return coroutine.yield(func, argc, ...)
  end
end

---Use this to create a function which executes in an async context but
---called from a non-async context. Inherently this cannot return anything
---since it is non-blocking
---@param func function
function M.void(func)
  return function(...)
    if coroutine.running() then
      return func(...)
    end
    execute(func, ...)
  end
end

---An async function that when called will yield to the Neovim scheduler to be
---able to call the API.
M.scheduler = M.wrap(vim.schedule, 1)

return M
