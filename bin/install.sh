#!/usr/bin/env bash
# Installe le CLI omarchy-prompt-correcter dans ~/.local/bin.
#   ./install.sh             lien du CLI uniquement
#   ./install.sh --bindings  ajoute aussi les raccourcis Hyprland
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
BIN="$HOME/.local/bin"
BINDINGS="$HOME/.config/hypr/bindings.lua"

mkdir -p "$BIN"
chmod +x "$DIR/omarchy-prompt-correcter"
ln -sf "$DIR/omarchy-prompt-correcter" "$BIN/omarchy-prompt-correcter"
echo "✓ omarchy-prompt-correcter lié dans $BIN"

if [ "${1:-}" = "--bindings" ]; then
  if ! grep -q "momoledev.prompt-correcter" "$BINDINGS" 2>/dev/null; then
    cat >> "$BINDINGS" <<'EOF'

-- Prompt Corrector (plugin momoledev.prompt-correcter)
o.bind("SUPER + ALT + C", "Prompt Corrector : panneau", "omarchy-shell -q shell toggle momoledev.prompt-correcter")
o.bind("SUPER + ALT + SHIFT + C", "Prompt Corrector : corriger le presse-papiers", "omarchy-prompt-correcter message --paste")
o.bind("SUPER + ALT + SHIFT + P", "Prompt Corrector : restructurer le presse-papiers", "omarchy-prompt-correcter prompt --paste")
EOF
    echo "✓ Raccourcis ajoutés à $BINDINGS (hyprctl reload si besoin)"
  else
    echo "• Raccourcis déjà présents dans $BINDINGS"
  fi
fi
