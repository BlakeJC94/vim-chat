# chat.vim
An asynchronous AI chat interface

## Usage

Launch a Chat session with `:Chat`
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

Coming soon:
- Session management
- Buffer and mapping customisation

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

### TODO
- [ ] Chat buffer
- [ ] Configuration
- [ ] History navigation

## Licence
Distributed under the same terms as Vim itself. See `:help license`.
