# Shared headless-Chrome resolution for the bin/ tools. Source this, then call resolve_chrome.
#
# Prefers chrome-headless-shell over full Chrome for Testing. On macOS 26, full Chrome's
# "new" headless mode stops producing frames on some builds: everything that needs one --
# Page.captureScreenshot, clicking an element, elementHandle.evaluate -- times out even on a
# trivial static page, while a plain page.evaluate keeps working, so the failure reads as a
# bug in the page under test.
#
# Cause unknown. Chrome version is the only discriminator found: 148 hangs 3/3 and 150
# succeeds 3/3 under identical conditions (measured 2026-08-06). An earlier note here blamed
# the macOS keychain and GPU compositor being unavailable in a GUI-less ssh context; that is
# wrong, since the machine had a logged-in console session throughout and a newer Chrome
# works there anyway. chrome-headless-shell has never shown the hang on any version, which
# is why it is preferred; upgrading past Chrome 148 also avoids it.
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

  # grep '^mac': the cache holds the downloaded .zip beside the unpacked build
  # directory, and an unfiltered `ls | tail -1` can select the archive, which
  # yields a nonsense path and the misleading "not found" error below.
  if [ -d "$shell_dir" ]; then
    v="$(ls "$shell_dir" | grep '^mac' | sort -V | tail -1)"
    CHROME_PATH="$shell_dir/$v/chrome-headless-shell-$arch/chrome-headless-shell"
    CHROME_HEADLESS_MODE="shell"
    CHROME_HEADLESS_JS="'shell'"
  fi

  # Fall back to full Chrome for Testing if the shell binary is not installed.
  if [ ! -x "$CHROME_PATH" ] && [ -d "$chrome_dir" ]; then
    v="$(ls "$chrome_dir" | grep '^mac' | sort -V | tail -1)"
    CHROME_PATH="$chrome_dir/$v/chrome-$arch/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
    CHROME_HEADLESS_MODE="full"
    CHROME_HEADLESS_JS="true"
  fi

  if [ ! -x "$CHROME_PATH" ]; then
    echo "Headless Chrome not found. Run: npx puppeteer browsers install chrome-headless-shell" >&2
    return 1
  fi
}
