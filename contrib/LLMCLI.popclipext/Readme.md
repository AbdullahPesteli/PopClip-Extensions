# PopClip LLM CLI Rewrite

Use a logged-in LLM command-line tool from PopClip to rewrite selected text.

This extension lets you select text anywhere on macOS, click a PopClip action, and send the selection to one of these CLIs:

- Codex CLI
- Claude CLI
- Gemini CLI
- OpenCode CLI
- Ollama

It is useful when you already pay for or are logged into a CLI tool and do not want to manage separate API keys inside PopClip.

## Features

- Uses existing CLI login/session state.
- No API key field in PopClip.
- Can use local Ollama preset models when available.
- Includes a native macOS picker mode for choosing provider/preset at runtime.
- Supports modifier-key shortcuts for quick provider/preset changes without opening settings.
- Supports multiple rewrite presets:
  - `Düzelt`: minimal Turkish spelling/punctuation correction.
  - `Chat Kurumsal`: clearer WhatsApp/Telegram work-message tone.
  - `Mail Kurumsal`: professional client-facing email tone.
  - `Müşteri Tonu`: warmer corporate client communication.
  - `Custom`: your own prompt from PopClip settings.
- Replaces the selected text with the model output.
- Supports optional model override per provider.

## Installation

1. Install and log in to at least one supported CLI.
2. Download or clone this repository.
3. Double-click `LLM-CLI.popclipext`.
4. Enable the extension in PopClip.
5. Open the extension settings and choose your provider.

If macOS/PopClip warns that the extension is unsigned, inspect the source first. The extension is a plain shell script plus a JSON config.

## Provider Setup

The extension expects the CLI to be available on `PATH`.

Common paths are already included:

- `~/.npm-global/bin`
- `~/.local/bin`
- `/opt/homebrew/bin`
- `/usr/local/bin`
- system paths

### Ollama

Default provider is Ollama because it works locally and gives immediate feedback when the expected local models exist.

Default local model mapping:

- `Düzelt` -> `turkce-duzelt`
- `Chat Kurumsal` -> `turkce-chat-kurumsal`
- `Mail Kurumsal` -> `turkce-mail-kurumsal`
- `Müşteri Tonu` -> `turkce-mail-musteri-tonu`

Set the Model field to override this mapping.

### Picker

Choose `Picker` as the provider to show a native macOS list each time the action runs. This is a workaround for PopClip's lack of extension-controlled submenus.

### Codex CLI

```sh
codex login
```

Codex works well for short non-interactive rewrite tasks. Choose it in the provider setting when you want a stronger cloud model.

### Claude CLI

```sh
claude
/login
```

Then choose `Claude CLI` in PopClip settings.

### Gemini CLI

```sh
gemini
```

Then complete the provider's login flow. Some Gemini CLI account tiers may not support the current CLI client.

### OpenCode CLI

```sh
opencode providers
```

Configure a provider, then choose `OpenCode CLI` in PopClip settings.

## Usage

1. Select text.
2. Click the `LLM CLI` PopClip action.
3. The selected text is replaced with the rewritten text.

Holding Shift with PopClip's `paste-result` behavior usually copies instead of pasting, depending on PopClip settings/version.

### Quick Modifier Shortcuts

Hold a modifier while clicking the PopClip action to bypass the configured provider/preset:

- No modifier: configured provider/preset.
- Option: Ollama / Chat Kurumsal.
- Shift: Ollama / Mail Kurumsal.
- Control: Ollama / Müşteri Tonu.
- Command: Codex / Düzelt.
- Command + Option: Codex / Chat Kurumsal.
- Command + Shift: Codex / Mail Kurumsal.
- Command + Control: open Picker.

## Notes

- This extension sends selected text to whichever third-party CLI/provider you choose.
- Do not use it on sensitive text unless you trust that provider and its account/data settings.
- CLIs can be slower than a local Ollama model. In testing, Codex was usable for short text, while OpenCode was slower.
- The output quality depends heavily on the provider, model, and prompt.
- Reasoning models are not automatically better for this workflow. For PopClip, the best model is usually the one that follows instructions and returns only clean final text.

## Development

See [CONTEXT.md](CONTEXT.md) for project background, PopClip API constraints,
known provider behavior, test cases, and suggested next improvements.

Test the script from Terminal:

```sh
env POPCLIP_OPTION_PROVIDER=codex POPCLIP_OPTION_PRESET=duzelt POPCLIP_OPTION_MODEL='' \
  ./LLM-CLI.popclipext/rewrite.zsh <<'EOF'
bu metni düzgün hale getirirmisin ama anlamı bozma
EOF
```

Create a distributable zip:

```sh
zip -r dist/LLM-CLI.popclipext.zip LLM-CLI.popclipext
```

## License

MIT
