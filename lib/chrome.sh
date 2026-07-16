# Shared headless-Chrome resolution for the bin/ tools. Source this, then call resolve_chrome.
#
# Prefers chrome-headless-shell over full Chrome for Testing: full Chrome's "new" headless
# mode initializes the macOS keychain and the GPU compositor, and BOTH hang in a GUI-less
# context (ssh session to a headless/locked Mac) -- Page.captureScreenshot times out even on
# a trivial static page. chrome-headless-shell (the classic headless implementation) depends
# on neither and captures reliably everywhere. Diagnosed 2026-07-15 on homebase over ssh.
#
# Sets:
#   CHROME_PATH          binary to pass as puppeteer executablePath
#   CHROME_HEADLESS_MODE 'shell' (chrome-headless-shell) or 'full' (Chrome for Testing)
#   CHROME_HEADLESS_JS   JS literal for puppeteer launch { headless: ... }
#                        ('shell' for the shell binary, true for full Chrome)
resolve_chrome() {
  local arch shell_dir="$HOME/.cache/puppeteer/chrome-headless-shell" chrome_dir="$HOME/.cache/puppeteer/chrome" v
  if [ "$(uname -m)" = "arm64" ]; then arch="mac-arm64"; else arch="mac-x64"; fi

  CHROME_PATH=""
  CHROME_HEADLESS_MODE="full"
  CHROME_HEADLESS_JS="true"

  if [ -d "$shell_dir" ]; then
    v="$(ls "$shell_dir" | sort -V | tail -1)"
    CHROME_PATH="$shell_dir/$v/chrome-headless-shell-$arch/chrome-headless-shell"
    CHROME_HEADLESS_MODE="shell"
    CHROME_HEADLESS_JS="'shell'"
  fi

  # Fall back to full Chrome for Testing if the shell binary is not installed.
  if [ ! -x "$CHROME_PATH" ] && [ -d "$chrome_dir" ]; then
    v="$(ls "$chrome_dir" | sort -V | tail -1)"
    CHROME_PATH="$chrome_dir/$v/chrome-$arch/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
    CHROME_HEADLESS_MODE="full"
    CHROME_HEADLESS_JS="true"
  fi

  if [ ! -x "$CHROME_PATH" ]; then
    echo "Headless Chrome not found. Run: npx puppeteer browsers install chrome-headless-shell" >&2
    return 1
  fi
}
