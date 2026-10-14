
<p align="center">
  <img src="assets/ipatente-quiz.png" width="128" alt="iPatente Quiz icon">
</p>

<h1 align="center">iPatente Quiz for Linux</h1>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Linux-2ea44f?logo=linux&logoColor=white" alt="Linux">
  <img src="https://img.shields.io/badge/runtime-Wine-7b68ee?logo=wine&logoColor=white" alt="Wine">
  <img src="https://img.shields.io/badge/script-Bash-4eaa25?logo=gnubash&logoColor=white" alt="Bash">
</p>

An installer for running the Windows/UWP build of iPatente Quiz on Linux with
Wine. It starts from an `.msixbundle` you have already obtained: the script
never downloads the application package itself.

## Table of contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Install](#install)
- [Launch](#launch)
- [Options](#options)
- [Uninstall](#uninstall)
- [Disclaimer](#disclaimer)

## What it does

- Extracts the correct APPX payload from an MSIX/AppX bundle.
- Unpacks `app/resources/app.asar`, which is needed for the application to run
  correctly in Wine.
- Creates a dedicated Wine prefix and application-menu launcher.
- Registers the iPatente Quiz icon with the desktop environment.
- Installs Framework7, Material Icons, Microsoft Core Fonts, and Noto Color
  Emoji into the WINEPREFIX, so as not to break the app (you can disable font installation with `--no-fonts`).

## Requirements

Required commands are `wine`, `7z`, `unzip`, and `asar`. The script checks for
them before changing anything. It detects common Debian/Ubuntu, Fedora/RHEL,
Arch/Manjaro, and openSUSE systems and suggests an installation command.

`curl` and `winetricks` are recommended. They install extra icon, text, and
emoji fonts in the isolated Wine prefix. Font downloads are optional and can be
disabled with `--no-fonts`. The installer uses a small spinner with elapsed
time for longer setup steps. During font downloads, curl shows the transfer
percentage, elapsed time, and estimated time remaining.

## Install

Make the script executable and give it your .msixbundle:

```bash
chmod +x install.sh
./install.sh /path/to/iPatenteQuiz.msixbundle
```

You can also run `./install.sh` by itself; it will ask for the bundle's path.

To also create a Desktop launcher:

```bash
./install.sh --desktop /path/to/iPatenteQuiz.msixbundle
```

By default, the application is installed to `~/.local/share/iPatenteQuiz` and
uses the isolated prefix `~/.wine-ipatente-quiz`. Reinstalling preserves the
previous application directory as a timestamped backup.

## Launch

Open **iPatente Quiz** from the application menu, or run:

```bash
ipatente-quiz
```

## Options

```text
--desktop              also create a launcher on the desktop
--no-fonts             skip downloaded and supplementary fonts
--verbose              show detailed extraction and font setup output
--app-dir DIRECTORY    custom application directory
--wineprefix DIRECTORY custom Wine prefix directory
--uninstall            remove the app, prefix, launchers, icon, and backups
```

For all options, run `./install.sh --help`.

## Uninstall

```bash
./install.sh --uninstall
```

If a custom application directory or Wine prefix was used, provide the same
values to the uninstall command:

```bash
./install.sh --uninstall \
  --app-dir /custom/path/iPatenteQuiz \
  --wineprefix /custom/path/wine-ipatente-quiz
```



