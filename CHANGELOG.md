# Changelog

## 1.0.0 - 2025-02-22
### Breaking changes
- Format for saved chats is now `*.chat` instead of `*.chat.vim.json`


## 0.3.0 - 2025-02-19
### Added
- Support for multiple configs
- Added arg for `:Chat` to select config
- Prompt to select config if unset
- Commands `:ChatStart` and `:ChatStop`
- Plug mappings `<plug>(chat-start)` and `<plug>(chat-stop)`
- Completion for `Chat` command
- Commands `:ChatSearch` and `:ChatGrep` for searching chats and placing in quickfix
- Added basic support for neovim


## 0.2.0 - 2025-02-19
### Added
- Authenticated endpoints via `g:vim_chat_config['token_var']`
- Configurable system prompts via `g:vim_chat_config['system_prompt']`

### Changed
- Progress message prints to buffer

### Fixed
- Generated filename now uses minutes correctly

## 0.1.0 - 2025-02-17
### Added
- New `chat` filetype
- Autocommand to render chats from `\*.chat.vim.json` files
- Display "In progress" message when awaiting a response

### Changed
- Multiple Chat buffer support


## 0.0.1 - 2025-02-09
### Added
- Initial version
- Basic configuration of endpoint and model
- Command `:Chat` to open a dedicated chat buffer
- Local mappings `<CR>` and `<BS>` to start/stop chat requests
