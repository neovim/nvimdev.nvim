;; extends

; pcall(exec_lua, [[code]])
(
  (function_call
    name: (identifier)
    arguments: (arguments
      (identifier) @_exec_lua
      (string
        content: (string_content) @injection.content
      )
    )
  )
  (#set! injection.language lua)
  (#eq? @_exec_lua "exec_lua")
)

; exec_lua([[code]])
(
  (function_call
    name: (identifier) @_exec_lua
    arguments: (arguments
      (string
        content: (string_content) @injection.content)
    )
  )
  (#set! injection.language lua)
  (#eq? @_exec_lua "exec_lua")
)

(
  (function_call
    (identifier) @_exec
    (arguments
      (string) @injection.content)
  )
  (#set! injection.language vim)
  (#eq? @_exec "exec")
  (#lua-match? @injection.content "^%[%[")
  (#offset! @injection.content 0 2 0 -2)
)

(
  (function_call
    (identifier) @_exec
    (arguments
      (string) @injection.content)
  )
  (#set! injection.language vim)
  (#eq? @_exec "exec")
  (#lua-match? @injection.content "^[\"']")
  (#offset! @injection.content 0 1 0 -1)
)
