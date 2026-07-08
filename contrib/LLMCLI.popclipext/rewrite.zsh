#!/bin/zsh
set -euo pipefail

export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# PopClip's shell PATH can be thinner than an interactive terminal. Cover common
# Homebrew, npm, and system locations without hard-coding a single machine.
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

interaction="${POPCLIP_OPTION_INTERACTION:-picker}"
provider="${POPCLIP_OPTION_PROVIDER:-ollama}"
preset="${POPCLIP_OPTION_PRESET:-duzelt}"
model="${POPCLIP_OPTION_MODEL:-}"
custom_prompt="${POPCLIP_OPTION_CUSTOMPROMPT:-}"
menu_config_path="${POPCLIP_OPTION_MENUCONFIG:-}"
modifier_flags="${POPCLIP_MODIFIER_FLAGS:-0}"
# Self-fixing is ON by default: on a failure the extension auto-repairs what it
# can (start Ollama, restore a missing model, fall back to a working provider)
# instead of leaving the user stuck. Set the "Auto Fix" option to off to disable.
auto_fix="${POPCLIP_OPTION_AUTOFIX:-1}"
input="$(cat)"
extension_dir="${0:A:h}"
cli_timeout_seconds="${POPCLIP_OPTION_TIMEOUTSECONDS:-25}"
case "$cli_timeout_seconds" in
  ''|*[!0-9]*) cli_timeout_seconds=25 ;;
esac

# ---------------------------------------------------------------------------
# User-facing messaging
# ---------------------------------------------------------------------------

fail() {
  # Never fail silently: show a clear macOS dialog with the reason + a fix hint,
  # then stop without replacing the selected text. This is the last resort, used
  # only when auto-repair and every fallback have already been exhausted.
  FAIL_MSG="$1" osascript -l JavaScript <<'JXA' >/dev/null 2>&1 || true
ObjC.import('stdlib')
const msg = ObjC.unwrap($.getenv('FAIL_MSG')) || 'LLM CLI: bilinmeyen hata'
const app = Application.currentApplication()
app.includeStandardAdditions = true
try {
  app.displayDialog(msg, { buttons: ['Tamam'], defaultButton: 'Tamam', withTitle: 'LLM CLI — sorun', withIcon: 'caution' })
} catch (e) {}
JXA
  exit 1
}

notify() {
  # Non-blocking, honest heads-up when the extension auto-fixed something or fell
  # back to a different provider. The user is never misled about what happened.
  NOTE_MSG="$1" osascript -l JavaScript <<'JXA' >/dev/null 2>&1 || true
ObjC.import('stdlib')
const msg = ObjC.unwrap($.getenv('NOTE_MSG')) || ''
const app = Application.currentApplication()
app.includeStandardAdditions = true
try { app.displayNotification(msg, { withTitle: 'LLM CLI', subtitle: 'otomatik onarım' }) } catch (e) {}
JXA
}

info_dialog() {
  INFO_MSG="$1" osascript -l JavaScript <<'JXA' >/dev/null 2>&1 || true
ObjC.import('stdlib')
const msg = ObjC.unwrap($.getenv('INFO_MSG')) || ''
const app = Application.currentApplication()
app.includeStandardAdditions = true
try { app.displayDialog(msg, { buttons: ['Tamam'], defaultButton: 'Tamam', withTitle: 'LLM CLI — Sağlık / Onarım' }) } catch (e) {}
JXA
}

show_help() {
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
display dialog "Click: model / preset picker
⌥ Option: Ollama / Chat
⇧ Shift: Ollama / Mail
⌃ Control: Ollama / Müşteri Tonu
⌘ Command: Codex / Düzelt
⌘⌥: Codex / Chat
⌘⇧: Codex / Mail
⌘⌃: Picker" buttons {"OK"} default button "OK" with title "LLM CLI Shortcuts"
APPLESCRIPT
}

# ---------------------------------------------------------------------------
# Menu config
# ---------------------------------------------------------------------------

ensure_menu_config() {
  if [[ -z "$menu_config_path" ]]; then
    menu_config_path="$HOME/.config/popclip-llm-cli-rewrite/menu.json"
  fi

  if [[ -f "$menu_config_path" ]]; then
    return
  fi

  mkdir -p "${menu_config_path:h}"
  cat >"$menu_config_path" <<'JSON'
{
  "items": [
    { "label": "Ollama - Düzelt", "provider": "ollama", "preset": "duzelt" },
    { "label": "⌥ Ollama - Chat Kurumsal", "provider": "ollama", "preset": "chat" },
    { "label": "⇧ Ollama - Mail Kurumsal", "provider": "ollama", "preset": "mail" },
    { "label": "⌃ Ollama - Müşteri Tonu", "provider": "ollama", "preset": "musteri" },
    { "separator": true },
    { "label": "⌘ Codex - Düzelt", "provider": "codex", "preset": "duzelt" },
    { "label": "⌘⌥ Codex - Chat Kurumsal", "provider": "codex", "preset": "chat" },
    { "label": "⌘⇧ Codex - Mail Kurumsal", "provider": "codex", "preset": "mail" },
    { "label": "Codex - Müşteri Tonu", "provider": "codex", "preset": "musteri" },
    { "separator": true },
    { "label": "🩺 Sağlık / Onar", "action": "doctor" },
    { "label": "Menüyü Düzenle", "action": "editMenu" },
    { "label": "Shortcut Help", "action": "help" }
  ]
}
JSON
}

open_menu_config() {
  ensure_menu_config
  if command -v code >/dev/null 2>&1; then
    code "$menu_config_path" >/dev/null 2>&1 || open -a TextEdit "$menu_config_path" >/dev/null 2>&1 || true
  else
    open -a TextEdit "$menu_config_path" >/dev/null 2>&1 || open "$menu_config_path" >/dev/null 2>&1 || true
  fi
}

launch_menu_editor() {
  # Open the native drag-and-drop menu editor. Falls back to opening the raw JSON
  # in a text editor if Swift is unavailable or compilation fails.
  ensure_menu_config
  local src="$extension_dir/menu-editor.swift"
  local cache_dir="$HOME/Library/Caches/PopClipLLMCLI"
  local bin="$cache_dir/menu-editor"
  mkdir -p "$cache_dir"
  if [[ -f "$src" ]] && command -v swiftc >/dev/null 2>&1; then
    if [[ ! -x "$bin" || "$src" -nt "$bin" ]]; then
      swiftc "$src" -o "$bin" >/dev/null 2>&1 || { open_menu_config; return; }
    fi
    # Detach so PopClip's script returns immediately (editor lives on its own).
    "$bin" "$menu_config_path" >/dev/null 2>&1 &
    disown
  else
    open_menu_config
  fi
}

apply_menu_choice() {
  local menu_item_json="$1"
  local assignments
  assignments="$(MENU_ITEM_JSON="$menu_item_json" osascript -l JavaScript <<'JXA'
ObjC.import('stdlib')

function shellQuote(value) {
  const text = value == null ? '' : String(value)
  return "'" + text.replace(/'/g, "'\\''") + "'"
}

const raw = ObjC.unwrap($.getenv('MENU_ITEM_JSON')) || '{}'
const item = JSON.parse(raw)
let output = ''
for (const key of ['action', 'provider', 'preset', 'model', 'customPrompt']) {
  output += `selected_${key}=${shellQuote(item[key])}\n`
}
output
JXA
)"
  eval "$assignments"

  if [[ "${selected_action:-}" == "help" ]]; then
    show_help
    exit 1
  fi

  if [[ "${selected_action:-}" == "editMenu" ]]; then
    launch_menu_editor
    exit 0
  fi

  if [[ "${selected_action:-}" == "doctor" ]]; then
    run_doctor
    exit 1
  fi

  [[ -n "${selected_provider:-}" ]] && provider="$selected_provider"
  [[ -n "${selected_preset:-}" ]] && preset="$selected_preset"
  [[ -n "${selected_model:-}" ]] && model="$selected_model"
  [[ -n "${selected_customPrompt:-}" ]] && custom_prompt="$selected_customPrompt"
  # A trailing conditional that evaluates false makes this function return
  # non-zero, which under `set -e` at the call site would abort the whole script
  # (this is exactly what silently broke the picker path). Force success.
  return 0
}

# ---------------------------------------------------------------------------
# Ollama health + self-repair
# ---------------------------------------------------------------------------

ollama_tags() {
  curl -fsS --max-time 5 http://127.0.0.1:11434/api/tags 2>/dev/null
}

ollama_up() {
  curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1
}

ensure_ollama_server() {
  # Start Ollama if it is not answering. `open -a Ollama` is a no-op when the app
  # is already running (never restarts a live app), so this is safe.
  ollama_up && return 0
  open -a Ollama >/dev/null 2>&1 || { command -v ollama >/dev/null 2>&1 && (ollama serve >/dev/null 2>&1 &); }
  local i
  for i in {1..15}; do
    ollama_up && { [[ "$i" -gt 1 ]] && notify "Ollama otomatik başlatıldı."; return 0; }
    sleep 1
  done
  return 1
}

active_ollama_store() {
  # The models directory the running server actually reads (may be an external
  # drive). Parsed from the server log; falls back to the default local store.
  local s
  s="$(grep -oE 'OLLAMA_MODELS:[^ ]+' "$HOME/.ollama/logs/server.log" 2>/dev/null | tail -1 | sed 's/OLLAMA_MODELS://')"
  if [[ -n "$s" ]]; then
    print -r -- "$s"
  else
    print -r -- "${OLLAMA_MODELS:-$HOME/.ollama/models}"
  fi
}

ollama_has_model() {
  ollama_tags | grep -qE "\"name\":\"${1}(:|\")"
}

heal_ollama_model() {
  # THE self-fix for the recurring trauma: a model that exists in SOME ollama
  # store but not the active one (store-location mismatch) is restored by copying
  # its manifest + missing blobs into the active store. Returns 0 if present after.
  local m="$1"
  ollama_has_model "$m" && return 0

  local active
  active="$(active_ollama_store)"

  local healed=1
  ACTIVE_STORE="$active" MODEL_NAME="$m" ALT_STORE="${OLLAMA_MODELS:-}" python3 <<'PY' && healed=0
import json, os, shutil, sys

active = os.path.expanduser(os.environ["ACTIVE_STORE"])
model  = os.environ["MODEL_NAME"]
alt    = os.environ.get("ALT_STORE", "")

# Candidate source stores to recover FROM (skip the active one).
candidates = [os.path.expanduser("~/.ollama/models")]
if alt:
    candidates.append(os.path.expanduser(alt))

def manifest_path(store):
    return os.path.join(store, "manifests/registry.ollama.ai/library", model, "latest")

for src in candidates:
    if os.path.abspath(src) == os.path.abspath(active):
        continue
    man = manifest_path(src)
    if not os.path.isfile(man):
        continue
    try:
        data = json.load(open(man))
    except Exception:
        continue
    digests = [data["config"]["digest"]] + [l["digest"] for l in data.get("layers", [])]
    src_blobs = os.path.join(src, "blobs")
    dst_blobs = os.path.join(active, "blobs")
    os.makedirs(dst_blobs, exist_ok=True)
    ok = True
    for d in digests:
        fn = d.replace(":", "-")
        s = os.path.join(src_blobs, fn)
        t = os.path.join(dst_blobs, fn)
        if os.path.exists(t):
            continue
        if not os.path.exists(s):
            ok = False
            break
        tmp = t + ".partial"
        shutil.copyfile(s, tmp)
        os.replace(tmp, t)
    if not ok:
        continue
    dst_man = manifest_path(active)
    os.makedirs(os.path.dirname(dst_man), exist_ok=True)
    shutil.copyfile(man, dst_man)
    sys.exit(0)   # restored
sys.exit(1)       # nothing to restore from
PY

  if [[ "$healed" -eq 0 ]] && ollama_has_model "$m"; then
    notify "Ollama modeli '$m' otomatik geri yüklendi."
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Doctor: manual "check + repair everything" action
# ---------------------------------------------------------------------------

run_doctor() {
  local report="🩺 LLM CLI — Sağlık Raporu"$'\n'
  local line

  # CLIs
  local c
  for c in ollama codex claude gemini opencode; do
    if command -v "$c" >/dev/null 2>&1; then
      report+=$'\n'"✅ CLI: $c"
    else
      report+=$'\n'"❌ CLI: $c yok"
    fi
  done

  # Ollama server (auto-start)
  report+=$'\n'
  if ensure_ollama_server; then
    report+=$'\n'"✅ Ollama sunucusu çalışıyor"
    report+=$'\n'"   depo: $(active_ollama_store)"
    # Models (auto-heal)
    local m
    for m in turkce-duzelt turkce-chat-kurumsal turkce-mail-kurumsal turkce-mail-musteri-tonu; do
      if ollama_has_model "$m"; then
        report+=$'\n'"✅ model: $m"
      elif heal_ollama_model "$m"; then
        report+=$'\n'"🔧 model: $m (otomatik geri yüklendi)"
      else
        report+=$'\n'"❌ model: $m yok (başka depoda da bulunamadı)"
      fi
    done
  else
    report+=$'\n'"❌ Ollama sunucusu başlatılamadı"
  fi

  # Codex login
  report+=$'\n'
  if command -v codex >/dev/null 2>&1; then
    if codex login status 2>&1 | grep -qi "logged in"; then
      report+=$'\n'"✅ Codex girişli"
    else
      report+=$'\n'"⚠️ Codex girişsiz — 'codex login'"
    fi
  fi

  info_dialog "$report"
}

# ---------------------------------------------------------------------------
# Interaction routing (modifiers / picker)
# ---------------------------------------------------------------------------

# Fast path: PopClip passes modifier keys to shell scripts. This gives one-icon
# quick selection without native submenu support.
used_modifier_shortcut=0
case "$modifier_flags" in
  524288) provider="ollama"; preset="chat"; used_modifier_shortcut=1 ;;       # Option
  131072) provider="ollama"; preset="mail"; used_modifier_shortcut=1 ;;       # Shift
  262144) provider="ollama"; preset="musteri"; used_modifier_shortcut=1 ;;    # Control
  1048576) provider="codex"; preset="duzelt"; used_modifier_shortcut=1 ;;     # Command
  1572864) provider="codex"; preset="chat"; used_modifier_shortcut=1 ;;       # Command + Option
  1179648) provider="codex"; preset="mail"; used_modifier_shortcut=1 ;;       # Command + Shift
  1310720) provider="picker"; used_modifier_shortcut=1 ;;                     # Command + Control
esac

if [[ "$used_modifier_shortcut" -eq 0 && "$interaction" == "picker" ]]; then
  provider="picker"
fi

if [[ "$provider" == "picker" ]]; then
  ensure_menu_config

  picker_helper() {
    local src="$extension_dir/picker-helper.swift"
    local cache_dir="$HOME/Library/Caches/PopClipLLMCLI"
    local bin="$cache_dir/picker-helper"
    mkdir -p "$cache_dir"
    if [[ ! -x "$bin" || "$src" -nt "$bin" ]]; then
      command -v swiftc >/dev/null 2>&1 || return 127
      swiftc "$src" -o "$bin" >/dev/null 2>&1 || return 127
    fi
    "$bin" "$menu_config_path"
  }

  set +e
  choice="$(picker_helper 2>/dev/null)"
  picker_status=$?
  set -e

  if [[ "$picker_status" -ne 0 ]]; then
    exit 1
  fi

  apply_menu_choice "$choice"

  if [[ -z "${provider:-}" || -z "${preset:-}" ]]; then
    exit 1
  fi
fi

if [[ "$provider" == "help" ]]; then
  show_help
  exit 1
fi

if [[ "$provider" == "doctor" ]]; then
  run_doctor
  exit 1
fi

# ---------------------------------------------------------------------------
# Prompt construction
# ---------------------------------------------------------------------------

case "$preset" in
  duzelt)
    instruction='You are a minimal Turkish text corrector. Do not answer questions; only return the corrected version of the user text. Preserve meaning, intent, negation, uncertainty, speaker perspective, names, links, model names, commands, and UI terms. Fix only spelling, punctuation, capitalization, question suffix spacing, obvious letter/suffix errors, and run-on sentence breaks. Do not make the text formal, corporate, literary, or artificial. Do not add explanations, headings, alternatives, comments, or new information.'
    ;;
  chat)
    instruction='You rewrite Turkish WhatsApp/Telegram work-group messages into a natural but clearer business chat tone. Never answer the user text; only rewrite the selected message. Preserve the speaker perspective. This is not an email: do not add greeting, closing, signature, or heavy formal language unless already present. Do not summarize long text. Preserve action direction for verbs such as çıkar, çıksın, ekle, kalsın, değişmesin, silinsin. Preserve revision ranges and timecodes exactly.'
    ;;
  mail)
    instruction='You rewrite Turkish email drafts into professional, clear, natural client-facing Turkish. Return only the rewritten email body. Preserve speaker perspective. If the draft is a note, keep it as a note; do not turn it into a representative answer. Do not add information, dates, budget, approvals, delivery promises, or links not present in the input. Preserve numeric ranges such as 1.23, 2.04-2.27, 00:15-00:22 exactly; do not reinterpret them as dates. Avoid heavy bureaucratic Turkish.'
    ;;
  musteri)
    instruction='You rewrite Turkish text into a corporate client communication tone. Never answer questions or requests in the selected text; only rewrite it. Preserve speaker perspective. Use clear, polite, warm but not artificially formal Turkish. Preserve links, dates, times, timecodes, names, brands, and project names. If the source is uncertain, keep the uncertainty. Do not add new brief details, budget, dates, approvals, links, or commitments.'
    ;;
  custom)
    instruction="$custom_prompt"
    ;;
  *)
    fail "Bilinmeyen preset: $preset"
    ;;
esac

if [[ -z "${instruction//[[:space:]]/}" ]]; then
  fail "Custom Prompt boş. PopClip ayarında Custom Prompt alanını doldur."
fi

prompt="${instruction}

Rules:
- Return only the final rewritten text.
- Do not output Markdown, code fences, headings, options, analysis, or thinking text.
- Do not answer the text; rewrite it.
- Preserve punctuation style inside numeric ranges and timecodes exactly, for example 2.04-2.27 or 00:15-00:22.

Text:
${input}"

# ---------------------------------------------------------------------------
# Providers (each returns non-zero + stderr on failure so the caller can fall
# back; they NEVER hard-exit, so auto-fix/fallback stays in control)
# ---------------------------------------------------------------------------

require_command() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "'$1' komutu bulunamadı (kur + giriş yap)." >&2
  return 2
}

run_with_timeout() {
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout --kill-after=2s "${cli_timeout_seconds}s" "$@"
  else
    "$@"
  fi
}

ollama_model_for_preset() {
  case "$preset" in
    duzelt) printf "%s" "turkce-duzelt" ;;
    chat) printf "%s" "turkce-chat-kurumsal" ;;
    mail) printf "%s" "turkce-mail-kurumsal" ;;
    musteri) printf "%s" "turkce-mail-musteri-tonu" ;;
    custom)
      if [[ -n "$model" ]]; then
        printf "%s" "$model"
      else
        echo "Custom preset with Ollama requires Model to be set." >&2
        return 2
      fi
      ;;
    *) echo "Unknown preset: $preset" >&2; return 2 ;;
  esac
}

run_ollama() {
  # Pre-flight self-repair: make sure the server is up and (for a mapped preset
  # model) the model actually exists in the active store, restoring it if it only
  # lives in another store. If auto-fix is off we skip repair and just try.
  if [[ "$auto_fix" == "1" ]]; then
    ensure_ollama_server || { echo "Ollama sunucusu yanıt vermiyor / başlatılamadı." >&2; return 1; }
  elif ! ollama_up; then
    echo "Ollama sunucusu yanıt vermiyor (127.0.0.1:11434)." >&2
    return 1
  fi

  local selected_model content
  if [[ -n "$model" ]]; then
    selected_model="$model"
    content="$prompt"
  else
    selected_model="$(ollama_model_for_preset)" || return 2
    if [[ "$preset" == "custom" ]]; then content="$prompt"; else content="$input"; fi
    if ! ollama_has_model "$selected_model"; then
      if [[ "$auto_fix" == "1" ]] && heal_ollama_model "$selected_model"; then
        :  # restored, continue
      else
        echo "Ollama modeli '$selected_model' bulunamadı (başka depoda da yok)." >&2
        return 1
      fi
    fi
  fi

  local payload
  payload="$(MODEL="$selected_model" CONTENT="$content" osascript -l JavaScript <<'JXA'
ObjC.import('stdlib')
const model = ObjC.unwrap($.getenv('MODEL'))
const content = ObjC.unwrap($.getenv('CONTENT'))
JSON.stringify({ model, stream: false, messages: [{ role: 'user', content }] })
JXA
)"
  curl -fsS --max-time "$cli_timeout_seconds" http://127.0.0.1:11434/api/chat \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    | plutil -extract message.content raw -o - -
}

run_gemini() {
  require_command gemini || return $?
  if [[ -n "$model" ]]; then
    run_with_timeout gemini -m "$model" -p "$prompt" --output-format text
  else
    run_with_timeout gemini -p "$prompt" --output-format text
  fi
}

run_claude() {
  require_command claude || return $?
  if [[ -n "$model" ]]; then
    run_with_timeout claude -p --output-format text --no-session-persistence --model "$model" "$prompt"
  else
    run_with_timeout claude -p --output-format text --no-session-persistence "$prompt"
  fi
}

run_codex() {
  require_command codex || return $?
  # Capture the exit status with && / || (errexit-exempt) instead of set +e/-e,
  # which could otherwise leak errexit state back into the caller's fallback loop.
  local out status
  out="$(mktemp "${TMPDIR:-/tmp}/popclip-codex.XXXXXX")"
  if [[ -n "$model" ]]; then
    printf "%s" "$prompt" | run_with_timeout codex exec --model "$model" --sandbox read-only --skip-git-repo-check --ephemeral --output-last-message "$out" - >/dev/null && status=0 || status=$?
  else
    printf "%s" "$prompt" | run_with_timeout codex exec --sandbox read-only --skip-git-repo-check --ephemeral --output-last-message "$out" - >/dev/null && status=0 || status=$?
  fi
  if [[ "$status" -ne 0 ]]; then
    rm -f "$out"
    return "$status"
  fi
  cat "$out"
  rm -f "$out"
}

run_opencode() {
  require_command opencode || return $?
  if [[ -n "$model" ]]; then
    run_with_timeout opencode run --model "$model" -- "$prompt"
  else
    run_with_timeout opencode run -- "$prompt"
  fi
}

run_provider() {
  case "$1" in
    ollama) run_ollama ;;
    codex) run_codex ;;
    claude) run_claude ;;
    gemini) run_gemini ;;
    opencode) run_opencode ;;
    *) echo "Bilinmeyen sağlayıcı: $1" >&2; return 2 ;;
  esac
}

clean_output() {
  printf "%s" "$1" \
    | perl -CS -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g' \
    | sed -e '/^\[opencode-mobile\]/d' -e '/^> build · /d' \
    | sed -e 's/^[[:space:]]*```[[:alnum:]_-]*[[:space:]]*$//' -e 's/^[[:space:]]*```[[:space:]]*$//' \
    | sed -e '1{/^[[:space:]]*$/d;}' -e '${/^[[:space:]]*$/d;}'
}

# ---------------------------------------------------------------------------
# Execution with auto-fix + provider fallback
# ---------------------------------------------------------------------------

# Build the attempt chain: the chosen provider first, then (when auto-fix is on)
# the other known-good providers so a click is never left with nothing. Gemini is
# excluded from automatic fallback because its individual tier is unsupported, but
# it is still attempted when explicitly chosen.
typeset -a chain
chain=("$provider")
if [[ "$auto_fix" == "1" ]]; then
  for p in codex claude ollama opencode; do
    [[ "$p" == "$provider" ]] && continue
    chain+=("$p")
  done
fi

result=""
used=""
last_err=""
last_rc=0
for p in $chain; do
  err_file="$(mktemp "${TMPDIR:-/tmp}/popclip-llm-err.XXXXXX")"
  # Run each attempt inside a command substitution (its own subshell): a provider
  # can fail, time out, or even mangle shell options without ever killing this
  # loop. The && / || capture keeps errexit from acting on a failed attempt.
  raw="$(run_provider "$p" 2>"$err_file")" && rc=0 || rc=$?
  last_err="$(tail -3 "$err_file" 2>/dev/null)"
  rm -f "$err_file"

  cleaned="$(clean_output "$raw")"
  if [[ "$rc" -eq 0 && -n "${cleaned//[[:space:]]/}" ]]; then
    result="$cleaned"
    used="$p"
    break
  fi
  last_rc="$rc"
done

if [[ -z "$result" ]]; then
  hint=""
  case "$provider" in
    codex)    hint="Codex girişini kontrol et: codex login status" ;;
    claude)   hint="Claude girişini kontrol et: claude → /login" ;;
    gemini)   hint="Gemini hesabı CLI'ı desteklemiyor olabilir; Codex/Claude dene." ;;
    opencode) hint="OpenCode sağlayıcısını ayarla: opencode providers" ;;
    ollama)   hint="Ollama'yı aç / modeli kur. 🩺 Sağlık / Onar'ı dene." ;;
  esac
  if [[ "${last_rc:-0}" -eq 124 || "${last_rc:-0}" -eq 137 ]]; then
    hint="Zaman aşımı (${cli_timeout_seconds}s). Timeout Seconds değerini artır."
  fi
  tried="${(j:, :)chain}"
  fail "Hiçbir sağlayıcı sonuç veremedi.
Denenen: ${tried}

Son hata: ${last_err:-(mesaj yok)}

Öneri: ${hint}"
fi

# Honest: if a fallback provider produced the result, say so (non-blocking).
if [[ "$used" != "$provider" ]]; then
  notify "‘${provider}’ çalışmadı → ‘${used}’ ile yapıldı."
fi

printf "%s" "$result"
