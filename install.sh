#!/bin/bash
    set -e

    curl -fsSL https://raw.githubusercontent.com/LarsGravesen-invilink/3x-ui-csm/main/install.sh -o /tmp/3xcsm.sh
    chmod +x /tmp/3xcsm.sh
    bash /tmp/3xcsm.sh

chmod +x "$BIN"

bash /opt/3xcsm/3xcsm.sh --menu
