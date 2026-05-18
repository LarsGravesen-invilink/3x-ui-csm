#!/bin/bash
set -e

REPO="https://raw.githubusercontent.com/LarsGravesen-invilink/3x-ui-csm/main"
BASE_DIR="/opt/3xcsm"
BIN="/usr/local/bin/3xsub"

mkdir -p "$BASE_DIR"

curl -fsSL "$REPO/3xcsm.sh" -o "$BASE_DIR/3xcsm.sh"
chmod +x "$BASE_DIR/3xcsm.sh"

cat > "$BIN" <<EOF
#!/bin/bash
exec bash /opt/3xcsm/3xcsm.sh --menu "$@"
EOF

chmod +x "$BIN"

echo "DONE"
