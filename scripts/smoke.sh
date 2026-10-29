#!/bin/sh
# End-to-end smoke: builds a throwaway fixture, runs the plugin headless
# through comment -> thread float -> reply -> resolve, then checks the
# language server attaches. Exits non-zero on any failure.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q "$work" # the language server resolves its root from .git
cat > "$work/doc.md" <<'EOF'
# Smoke spec

Alpha paragraph first line
continues on a second line.

Beta paragraph after a blank.

Tail.
EOF

echo "== plugin flows =="
MDREV_LSP=0 nvim --headless -u "$root/scripts/smoke-init.lua" "$work/doc.md" \
	+"lua dofile([[$root/scripts/smoke.lua]])"

echo "== language server =="
timeout 20 nvim --headless -u "$root/scripts/smoke-init.lua" "$work/doc.md" \
	+'lua vim.wait(4000, function() return #vim.lsp.get_clients({bufnr=0}) > 0 end, 100); print("clients: "..#vim.lsp.get_clients({bufnr=0})); vim.cmd("qa!")' \
	2>&1 | grep -q "clients: 1" && echo "ok   lsp attaches" || {
	echo "FAIL lsp attaches"
	exit 1
}
