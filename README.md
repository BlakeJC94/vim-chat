# chat.vim
An asynchronous AI chat interface

## Requirements
- `curl`
- `ollama`

Integrations with other AI Chat services can be requested in the Github issues (or feel free to
open a pull request).

## Usage

Launch a Chat buffer with `:Chat`
```
>>> user

```

Enter your query and press `<CR>`, and this plugin will asynchronously update the chat buffer with
a response.

```
>>> user
In two sentences, explain what quaternions are

<<< user
>>> assistant
Quaternions are a mathematical system that extends complex numbers to four dimensions, consisting of
one real part and three imaginary parts. They are particularly useful in representing rotations in
three-dimensional space and have applications in computer graphics, robotics, and physics for
efficiently handling orientation calculations without the gimbal lock issue associated with Euler
angles.

<<< assistant
>>> user

```

All chats are saved locally to `g:vim_chat_path` (default: `~/.chat.vim`) as `*.chat.vim.json`
files. Past chats can be re-opened and continued by using `:edit` on any of these files.


## Installation
Use vim's built-in package support or your favourite package manager.

My suggested method is [`vim-plug`](https://github.com/junegunn/vim-plug)
```
Plug 'https://github.com/BlakeJC94/vim-chat'
```

This plugin can be configured using a dictionary in your `.vimrc`
```
let g:vim_chat_config = {
\  "model": "llama3.2:latest",
\  "endpoint_url": "http://localhost:11434/api/chat"
\}
```

*NOTE:* At this stage, only `ollama` is supported, but authenticated endpoints such as  `OpenAI` are
coming soon.

## Issues
If any errors are encountered (or you would like to make a feature request), raise an issue on the
repository so we can discuss. Pull requests are also welcomed

## Development
The `main` branch is reserved for releases and should be considered stable. Changes should occur in
the `dev` branch, which will periodically be merged into `main`.

## Licence
Distributed under the same terms as Vim itself. See `:help license`.
