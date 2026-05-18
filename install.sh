#!/bin/bash
    set -e

        REPO="https://raw.githubusercontent.com/LarsGravesen-invilink/3x-ui-csm/main"
        BASE_DIR="/opt/3xcsm"
        BIN="/usr/local/bin/3xsub"
        LOCAL_VERSION="1.0"

        REMOTE_VERSION=$(curl -fsSL "$REPO/version.txt" 2>/dev/null || echo "0")
        REMOTE_VERSION=$(echo "$REMOTE_VERSION" | tr -d '\n\r')

    echo "Local version: $LOCAL_VERSION"
    echo "Remote version: $REMOTE_VERSION"

    mkdir -p "$BASE_DIR"

    curl -fsSL "$REPO/3xcsm.sh" -o "$BASE_DIR/3xcsm.sh"
    chmod +x "$BASE_DIR/3xcsm.sh"

    cat > "$BIN" <<'EOF'
#!/bin/bash
exec bash /opt/3xcsm/3xcsm.sh --menu "$@"
EOF

    chmod +x "$BIN"

    echo "Установлена версия: $REMOTE_VERSION"
