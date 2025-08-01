local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')
local current_tokenizer = nil

--- @return string
local function get_lib_extension()
  if jit.os:lower() == 'mac' or jit.os:lower() == 'osx' then
    return '.dylib'
  end
  if jit.os:lower() == 'windows' then
    return '.dll'
  end
  return '.so'
end

package.cpath = package.cpath
  .. ';'
  .. debug.getinfo(1).source:match('@?(.*/)')
  .. '../../build/?'
  .. get_lib_extension()

local tiktoken_ok, tiktoken_core = pcall(require, 'tiktoken_core')
if not tiktoken_ok then
  tiktoken_core = nil
end

--- Load tiktoken data from cache or download it
---@param tokenizer string The tokenizer to load
---@async
local function load_tiktoken_data(tokenizer)
  utils.schedule_main()

  local tiktoken_url = 'https://openaipublic.blob.core.windows.net/encodings/' .. tokenizer .. '.tiktoken'

  local cache_dir = vim.fn.stdpath('cache')
  vim.fn.mkdir(tostring(cache_dir), 'p')
  local cache_path = cache_dir .. '/' .. tiktoken_url:match('.+/(.+)')

  if vim.uv.fs_stat(cache_path) then
    return cache_path
  end

  notify.publish(notify.STATUS, 'Downloading tiktoken data from ' .. tiktoken_url)

  utils.curl_get(tiktoken_url, {
    output = cache_path,
  })

  return cache_path
end

local M = {}

--- Load the tiktoken module
---@param tokenizer string The tokenizer to load
---@async
M.load = function(tokenizer)
  if not tiktoken_core then
    return
  end

  if tokenizer == current_tokenizer then
    return
  end

  local path = load_tiktoken_data(tokenizer)
  local special_tokens = {}
  special_tokens['<|endoftext|>'] = 100257
  special_tokens['<|fim_prefix|>'] = 100258
  special_tokens['<|fim_middle|>'] = 100259
  special_tokens['<|fim_suffix|>'] = 100260
  special_tokens['<|endofprompt|>'] = 100276
  local pat_str =
    "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}{1,3}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"

  utils.schedule_main()
  tiktoken_core.new(path, special_tokens, pat_str)
  current_tokenizer = tokenizer
end

--- Encode a prompt
---@param prompt string The prompt to encode
---@return table?
function M.encode(prompt)
  if not tiktoken_core then
    return nil
  end
  if not prompt or prompt == '' then
    return nil
  end
  -- Check if prompt is a string
  if type(prompt) ~= 'string' then
    error('Prompt must be a string')
  end

  local ok, result = pcall(tiktoken_core.encode, prompt)
  if not ok then
    return nil
  end

  return result
end

--- Count the tokens in a prompt
---@param prompt string The prompt to count
---@return number
function M.count(prompt)
  if not tiktoken_core then
    return math.ceil(#prompt * 0.5) -- Fallback to 1/2 character count
  end

  local tokens = M.encode(prompt)
  if not tokens then
    return math.ceil(#prompt * 0.5) -- Fallback to 1/2 character count
  end
  return #tokens
end

return M
