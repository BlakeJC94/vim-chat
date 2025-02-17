# Changelog

## Unreleased
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
