#!/usr/bin/env bash

set -euo pipefail

if command -v gfortran >/dev/null 2>&1; then
  echo "gfortran already installed:"
  gfortran --version | head -n 1
  exit 0
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "ERROR: sudo is required to install system packages." >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  echo "Detected Debian/Ubuntu package manager."
  sudo apt-get update
  sudo apt-get install -y gfortran
elif command -v dnf >/dev/null 2>&1; then
  echo "Detected Fedora/RHEL package manager."
  sudo dnf install -y gcc-gfortran
elif command -v yum >/dev/null 2>&1; then
  echo "Detected Legacy RHEL package manager."
  sudo yum install -y gcc-gfortran
elif command -v pacman >/dev/null 2>&1; then
  echo "Detected Arch package manager."
  sudo pacman -Syu --noconfirm gcc
elif command -v apk >/dev/null 2>&1; then
  echo "Detected Alpine package manager."
  sudo apk add --no-cache gfortran
elif command -v brew >/dev/null 2>&1; then
  echo "Detected Homebrew."
  brew install gcc
else
  echo "ERROR: No supported package manager found."
  echo "Please install gfortran manually for your OS."
  exit 1
fi

if command -v gfortran >/dev/null 2>&1; then
  echo "gfortran installation succeeded:"
  gfortran --version | head -n 1
else
  echo "ERROR: gfortran still not found after install attempt." >&2
  exit 1
fi

