#!/usr/bin/env bash
# Installs iPatente Quiz from an already downloaded .msixbundle file.
# Only supplementary fonts are downloaded; the application itself is never downloaded.

set -Eeuo pipefail

readonly APP_NAME='iPatente Quiz'
readonly APP_SLUG='ipatente-quiz'
readonly DEFAULT_APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/iPatenteQuiz"
readonly DEFAULT_WINEPREFIX="$HOME/.wine-ipatente-quiz"
readonly MATERIAL_ICONS_URL='https://raw.githubusercontent.com/google/material-design-icons/master/font/MaterialIcons-Regular.ttf'
# The Windows-compatible build is specifically suited to Wine/DirectWrite.
readonly NOTO_COLOR_EMOJI_URL='https://raw.githubusercontent.com/googlefonts/noto-emoji/main/2D/fonts/NotoColorEmoji.ttf'

APP_DIR="$DEFAULT_APP_DIR"
WINEPREFIX_DIR="$DEFAULT_WINEPREFIX"
ADD_DESKTOP=false
INSTALL_FONTS=true
UNINSTALL=false
VERBOSE=false
BUNDLE=''
WORK_DIR=''

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] FILE.msixbundle

Installs ${APP_NAME} in the current user's home directory and adds it to the
application menu. FILE.msixbundle must be an already downloaded local file.

Options:
  --uninstall            remove the app, its Wine prefix, launchers, and icon
  --desktop              also create a launcher on the desktop
  --no-fonts             do not download/install extra fonts in the Wine prefix
  --verbose              show detailed output from extraction and font setup
  --app-dir DIRECTORY    installation directory (default: $DEFAULT_APP_DIR)
  --wineprefix DIRECTORY Wine prefix directory (default: $DEFAULT_WINEPREFIX)
  -h, --help             show this help message
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }

run_step() {
  local label="$1"
  shift
  local log_file="$WORK_DIR/step.log"
  local started elapsed pid exit_code=0

  if $VERBOSE; then
    note "$label"
    "$@"
    return
  fi

  "$@" >"$log_file" 2>&1 &
  pid=$!
  started=$SECONDS
  local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local frame=0
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$((SECONDS - started))
    printf '\r  %s %s (%s elapsed)' "${frames[frame]}" "$label" "$(format_time "$elapsed")"
    frame=$(((frame + 1) % ${#frames[@]}))
    sleep 0.12
  done
  wait "$pid" || exit_code=$?
  elapsed=$((SECONDS - started))
  if ((exit_code == 0)); then
    printf '\r  ✓ %s (%s)\033[K\n' "$label" "$(format_time "$elapsed")"
  else
    printf '\r  ✗ %s failed (%s)\033[K\n' "$label" "$(format_time "$elapsed")" >&2
    [[ ! -s "$log_file" ]] || tail -n 20 "$log_file" >&2
    return "$exit_code"
  fi
}

format_time() {
  local seconds="$1"
  if ((seconds < 60)); then
    printf '%ss' "$seconds"
  else
    printf '%dm %02ds' "$((seconds / 60))" "$((seconds % 60))"
  fi
}

download_font() {
  local label="$1" url="$2" destination="$3" temporary_file="${3}.download"
  local -a curl_options=(--fail --location --retry 2 --show-error \
    --write-out '\nDownloaded in %{time_total}s (%{speed_download} bytes/s)\n')
  if $VERBOSE; then
    curl --verbose "${curl_options[@]}" "$url" -o "$temporary_file" || {
      rm -f -- "$temporary_file"
      return 1
    }
  else
    printf '  Downloading %s\n' "$label"
    # Curl's compact transfer meter reports percentage, elapsed time, and ETA.
    curl "${curl_options[@]}" "$url" -o "$temporary_file" || {
      rm -f -- "$temporary_file"
      return 1
    }
  fi
  mv -f -- "$temporary_file" "$destination"
}

cleanup() {
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

desktop_directory() {
  local directory="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
  local detected_directory
  if command -v xdg-user-dir >/dev/null 2>&1; then
    detected_directory="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    [[ -n "$detected_directory" ]] && directory="$detected_directory"
  fi
  printf '%s\n' "$directory"
}

refresh_desktop_caches() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$applications_dir" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache --force "$data_dir/icons/hicolor" >/dev/null 2>&1 || true
  fi
  # Plasma keeps its own service cache; support both Plasma 5 and Plasma 6.
  for command in kbuildsycoca6 kbuildsycoca5; do
    if command -v "$command" >/dev/null 2>&1; then
      "$command" --noincremental >/dev/null 2>&1 || true
      break
    fi
  done
}

safe_remove_directory() {
  local target="$1"
  [[ -n "$target" && "$target" != / && "$target" != "$HOME" ]] || \
    die "refusing to remove unsafe path: $target"
  [[ -e "$target" ]] && rm -rf -- "$target"
  return 0
}

distribution_install_hint() {
  local distribution_id=''
  local distribution_like=''
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    distribution_id="${ID:-}"
    distribution_like="${ID_LIKE:-}"
  fi

  case "$distribution_id $distribution_like" in
    *debian*|*ubuntu*)
      printf '%s\n' 'sudo apt install wine p7zip-full unzip node-asar curl winetricks'
      ;;
    *fedora*|*rhel*)
      printf '%s\n' 'sudo dnf install wine p7zip p7zip-plugins unzip nodejs-asar curl winetricks'
      ;;
    *arch*|*manjaro*)
      printf '%s\n' 'sudo pacman -S wine p7zip unzip asar curl winetricks'
      ;;
    *suse*|*opensuse*)
      printf '%s\n' 'sudo zypper install wine p7zip unzip nodejs-asar curl winetricks'
      ;;
    *)
      printf '%s\n' 'Install Wine, 7z/p7zip, unzip, the Electron asar CLI, curl, and winetricks with your distribution package manager.'
      ;;
  esac
}

check_dependencies() {
  local -a missing=()
  local command
  for command in 7z unzip asar wine; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
  done
  if ((${#missing[@]})); then
    printf 'Missing required commands: %s\n' "${missing[*]}" >&2
    printf 'Suggested command for this distribution:\n  %s\n' "$(distribution_install_hint)" >&2
    exit 1
  fi

  if $INSTALL_FONTS && ! command -v curl >/dev/null 2>&1; then
    printf 'Warning: curl is missing; icon and emoji fonts will be skipped.\n' >&2
    printf 'Suggested command for this distribution:\n  %s\n' "$(distribution_install_hint)" >&2
  fi
}

while (($#)); do
  case "$1" in
    --uninstall) UNINSTALL=true ;;
    --desktop) ADD_DESKTOP=true ;;
    --no-fonts) INSTALL_FONTS=false ;;
    --verbose) VERBOSE=true ;;
    --app-dir)
      (($# >= 2)) || die '--app-dir needs a directory'
      APP_DIR="$2"; shift ;;
    --wineprefix)
      (($# >= 2)) || die '--wineprefix needs a directory'
      WINEPREFIX_DIR="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown option: $1" ;;
    *)
      [[ -z "$BUNDLE" ]] || die 'provide only one .msixbundle file'
      BUNDLE="$1" ;;
  esac
  shift
done

bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
applications_dir="$data_dir/applications"
icons_dir="$data_dir/icons/hicolor/256x256/apps"
launcher="$bin_dir/$APP_SLUG"
desktop_file="$applications_dir/$APP_SLUG.desktop"
desktop_launcher="$(desktop_directory)/$APP_NAME.desktop"
icon_file="$icons_dir/$APP_SLUG.png"
user_emoji_fonts_dir="$data_dir/fonts/$APP_SLUG"

if $UNINSTALL; then
  note "Removing ${APP_NAME}"
  safe_remove_directory "$APP_DIR"
  safe_remove_directory "$WINEPREFIX_DIR"
  safe_remove_directory "$user_emoji_fonts_dir"
  shopt -s nullglob
  previous_installations=("$APP_DIR".previous.*)
  shopt -u nullglob
  ((${#previous_installations[@]} == 0)) || rm -rf -- "${previous_installations[@]}"
  rm -f -- "$launcher" "$desktop_file" "$desktop_launcher" "$icon_file"
  refresh_desktop_caches
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$data_dir/fonts" >/dev/null 2>&1 || true
  fi
  ok "${APP_NAME} has been uninstalled"
  exit 0
fi

if [[ -z "$BUNDLE" ]]; then
  if [[ -t 0 ]]; then
    printf '\nWelcome! First, download the iPatente Quiz .msixbundle yourself.\n'
    read -r -p 'Enter the full path to that file: ' BUNDLE
    BUNDLE="${BUNDLE#\"}"
    BUNDLE="${BUNDLE%\"}"
    BUNDLE="${BUNDLE#\'}"
    BUNDLE="${BUNDLE%\'}"
  else
    usage >&2
    exit 2
  fi
fi
[[ -n "$BUNDLE" ]] || die 'no bundle path was entered'
[[ -f "$BUNDLE" ]] || die "file not found: $BUNDLE"
case "${BUNDLE,,}" in
  *.msixbundle|*.appxbundle) ;;
  *) die 'the file must have a .msixbundle or .appxbundle extension' ;;
esac

check_dependencies

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ipatente-quiz.XXXXXX")"
readonly STAGE_DIR="$WORK_DIR/app"
readonly PACKAGE_FILE="$WORK_DIR/package.appx"

note 'Step 1/5: checking the Windows package in the bundle'
mapfile -t packages < <(unzip -Z1 "$BUNDLE" | grep -Ei '\.(msix|appx)$' || true)
((${#packages[@]})) || die 'the bundle contains no .appx or .msix package'

# Prefer x64; a neutral package is normally the universal fallback. A bundle
# can also contain x64 dependencies, so validate each candidate by its layout.
declare -a candidates=()
declare -A seen_candidates=()
for pattern in 'x64' 'neutral' ''; do
  for candidate in "${packages[@]}"; do
    if [[ -z "$pattern" || "${candidate,,}" == *"$pattern"* ]]; then
      if [[ -z "${seen_candidates[$candidate]+x}" ]]; then
        candidates+=("$candidate")
        seen_candidates["$candidate"]=1
      fi
    fi
  done
done

note 'Step 2/5: extracting the application'
# In this UWP APPX, executable content is inside the app/ subdirectory.
readonly PAYLOAD_DIR="$STAGE_DIR/app"
package_member=''
for candidate in "${candidates[@]}"; do
  rm -rf -- "$STAGE_DIR"
  rm -f -- "$PACKAGE_FILE"
  unzip -p "$BUNDLE" "$candidate" > "$PACKAGE_FILE"
  if 7z x -y "-o$STAGE_DIR" "$PACKAGE_FILE" >/dev/null 2>&1 && \
      [[ -f "$PAYLOAD_DIR/resources/app.asar" ]]; then
    package_member="$candidate"
    break
  fi
done
[[ -n "$package_member" ]] || die 'could not find an APPX package with app/resources/app.asar'
printf '  Selected package: %s\n' "$package_member"

asar_file="$PAYLOAD_DIR/resources/app.asar"
run_step 'Unpacking app.asar' asar extract "$asar_file" "$asar_file.extracted"
rm -f -- "$asar_file"
mv -- "$asar_file.extracted" "$asar_file"

exe_file="$(find "$PAYLOAD_DIR" -maxdepth 1 -type f -iname '*.exe' -print -quit)"
[[ -n "$exe_file" ]] || die 'main .exe file was not found in the extracted package'
exe_name="${exe_file##*/}"

note 'Step 3/5: installing application files'
mkdir -p "$(dirname "$APP_DIR")"
backup_dir=''
if [[ -e "$APP_DIR" ]]; then
  backup_dir="${APP_DIR}.previous.$(date +%Y%m%d-%H%M%S)"
  mv -- "$APP_DIR" "$backup_dir"
  printf '  Previous installation saved to: %s\n' "$backup_dir"
fi
mv -- "$PAYLOAD_DIR" "$APP_DIR"

if $INSTALL_FONTS; then
  note 'Step 4/5: setting up fonts and emoji support'
  # wineboot creates the prefix on a first installation before fonts are copied.
  run_step 'Preparing the Wine prefix' env WINEPREFIX="$WINEPREFIX_DIR" wineboot -u || true
  wine_fonts_dir="$WINEPREFIX_DIR/drive_c/windows/Fonts"
  user_fonts_dir="$user_emoji_fonts_dir"
  mkdir -p "$wine_fonts_dir"

  # Framework7 provides the UI-arrow glyphs and is already inside the bundle.
  framework_font="$APP_DIR/resources/www/fonts/Framework7Icons-Regular.ttf"
  if [[ -f "$framework_font" ]]; then
    cp -f -- "$framework_font" "$wine_fonts_dir/Framework7Icons-Regular.ttf"
  fi

  # The bundle contains Material Icons only as WOFF2. Wine reliably registers
  # TrueType fonts, so fetch the official Google TTF instead.
  if ! command -v curl >/dev/null 2>&1; then
    printf '  Warning: curl is unavailable; skipping downloaded icon and emoji fonts.\n' >&2
  else
    download_font 'Material Icons' "$MATERIAL_ICONS_URL" "$wine_fonts_dir/MaterialIcons-Regular.ttf" || \
      printf '  Warning: could not download Material Icons; continuing anyway.\n' >&2
    # Chromium under Wine can use either Windows fonts or the host fontconfig
    # database, so install Noto Color Emoji in both locations.
    mkdir -p "$user_fonts_dir"
    if download_font 'Noto Color Emoji' "$NOTO_COLOR_EMOJI_URL" "$wine_fonts_dir/NotoColorEmoji.ttf"; then
      cp -f -- "$wine_fonts_dir/NotoColorEmoji.ttf" "$user_fonts_dir/NotoColorEmoji.ttf"
      if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$user_fonts_dir" >/dev/null 2>&1 || true
      fi
    else
      printf '  Warning: could not download Noto Color Emoji; continuing anyway.\n' >&2
    fi
  fi

  # When available, winetricks also installs Arial, Verdana, Tahoma, Times New
  # Roman, and other Microsoft fonts commonly expected by webviews.
  if command -v winetricks >/dev/null 2>&1; then
    run_step 'Installing Microsoft Core Fonts' env WINEPREFIX="$WINEPREFIX_DIR" winetricks -q corefonts || \
      printf '  Warning: winetricks corefonts failed; continuing anyway.\n' >&2
  else
    printf '  Note: install winetricks to add Microsoft Core Fonts as well.\n' >&2
  fi
  run_step 'Refreshing Wine fonts' env WINEPREFIX="$WINEPREFIX_DIR" wineboot -u || true
fi

mkdir -p "$bin_dir" "$applications_dir"

# The APPX payload keeps web assets inside the extracted app.asar directory.
# Register the app's own square icon in hicolor and reference it by theme name;
# Plasma resolves this more reliably than an absolute path in Icon=.
desktop_icon="$APP_SLUG"
found_icon=false
for source_icon in \
  "$APP_DIR/resources/app.asar/www/img/app-icon.png" \
  "$APP_DIR/resources/app.asar/www/img/favicon.png" \
  "$APP_DIR/Assets/StoreLogo.png" \
  "$APP_DIR/Assets/Square150x150Logo.png" \
  "$APP_DIR/Assets/Square44x44Logo.png"; do
  if [[ -f "$source_icon" ]]; then
    mkdir -p "$icons_dir"
    cp -f -- "$source_icon" "$icon_file"
    found_icon=true
    break
  fi
done
if ! $found_icon; then
  die 'could not find an application icon in the extracted package; no Wine placeholder will be used'
fi

cat > "$launcher" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd '$APP_DIR'
exec env WINEPREFIX='$WINEPREFIX_DIR' WINEDEBUG=-all wine '$APP_DIR/$exe_name' "\$@"
EOF
chmod 755 "$launcher"

cat > "$desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=Italian driving-licence quiz practice
Exec=$launcher
Icon=$desktop_icon
Terminal=false
Categories=Education;Game;
StartupNotify=true
EOF
chmod 644 "$desktop_file"

if $ADD_DESKTOP; then
  desktop_dir="$(desktop_directory)"
  mkdir -p "$desktop_dir"
  cp -- "$desktop_file" "$desktop_dir/$APP_NAME.desktop"
  chmod 755 "$desktop_dir/$APP_NAME.desktop"
  ok 'Desktop launcher created'
fi

note 'Step 5/5: adding iPatente Quiz to the application menu'
refresh_desktop_caches

ok "${APP_NAME} is ready"
printf '  Application menu: %s\n' "$desktop_file"
printf '  Terminal launcher: %s\n' "$launcher"
printf '  Wine prefix: %s\n' "$WINEPREFIX_DIR"
