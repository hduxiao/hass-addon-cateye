#!/bin/sh
set -eu

ADDON_DIR="/config"
CONFIG_PATH="${ADDON_DIR}/client.toml"
DEFAULT_CONFIG_PATH="/client.toml"
LOG_DIR="${ADDON_DIR}/log"
CATEYE_BIN="/usr/local/bin/cateye"
NGINX_BIN="/usr/sbin/nginx"
NGINX_CONF_TEMPLATE="/ingress.conf.template"
NGINX_CONF="/tmp/nginx-cateye.conf"
WAIT_PIDS=""

log() {
    printf '[cateye-addon] %s\n' "$*"
}

append_pid() {
    WAIT_PIDS="${WAIT_PIDS} $1"
}

stop_all() {
    log "Stopping Cateye add-on"
    for pid in $WAIT_PIDS; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    for pid in $WAIT_PIDS; do
        wait "$pid" 2>/dev/null || true
    done
}

on_signal() {
    stop_all
    exit 0
}

trim() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

read_admin_value() {
    key="$1"
    awk -v key="$key" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }

        /^[[:space:]]*\[admin\][[:space:]]*$/ { in_admin=1; next }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ { in_admin=0 }
        in_admin {
            line=$0
            if (line ~ "^[[:space:]]*" key "[[:space:]]*=") {
                sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
                line = trim(line)

                if (line ~ /^"/) {
                    value = ""
                    escape = 0
                    for (i = 2; i <= length(line); ++i) {
                        ch = substr(line, i, 1)
                        if (escape) {
                            value = value ch
                            escape = 0
                        } else if (ch == "\\") {
                            escape = 1
                        } else if (ch == "\"") {
                            print value
                            exit
                        } else {
                            value = value ch
                        }
                    }
                    print value
                    exit
                }

                sub(/[[:space:]]*#.*/, "", line)
                print trim(line)
                exit
            }
        }
    ' "$CONFIG_PATH"
}

validate_admin_config() {
    admin_enabled="$(trim "$(read_admin_value enabled)")"
    admin_bind_addr="$(trim "$(read_admin_value bind_addr)")"
    admin_port="$(trim "$(read_admin_value port)")"
    admin_username="$(read_admin_value username)"
    admin_password="$(read_admin_value password)"

    if [ "$admin_enabled" != "true" ]; then
        log "Ingress requires [admin].enabled = true in $CONFIG_PATH"
        exit 1
    fi
    if [ "$admin_bind_addr" != "127.0.0.1" ]; then
        log "Ingress requires [admin].bind_addr = \"127.0.0.1\" in $CONFIG_PATH"
        exit 1
    fi
    case "$admin_port" in
        ''|*[!0-9]*)
            log "Ingress requires numeric [admin].port in $CONFIG_PATH"
            exit 1
            ;;
    esac
    if [ "$admin_port" -lt 1 ] || [ "$admin_port" -gt 65535 ]; then
        log "Ingress requires [admin].port to be within 1-65535 in $CONFIG_PATH"
        exit 1
    fi
    if [ -z "$admin_username" ] || [ -z "$admin_password" ]; then
        log "Ingress requires non-empty [admin].username and [admin].password in $CONFIG_PATH"
        exit 1
    fi
}

render_nginx_config() {
    basic_auth="$(printf '%s:%s' "$admin_username" "$admin_password" | base64 | tr -d '\n')"
    sed \
        -e "s|__BASIC_AUTH__|$basic_auth|g" \
        -e "s|__ADMIN_PORT__|$admin_port|g" \
        "$NGINX_CONF_TEMPLATE" > "$NGINX_CONF"
}

start_nginx() {
    "$NGINX_BIN" -c "$NGINX_CONF" -g 'daemon off;' &
    append_pid "$!"
}

start_config_watcher() {
    (
        last_mtime=""
        while :; do
            current_mtime="$(stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "")"
            if [ -n "$current_mtime" ] && [ "$current_mtime" != "$last_mtime" ]; then
                last_mtime="$current_mtime"
                validate_admin_config
                render_nginx_config
                if [ -s "$NGINX_CONF" ]; then
                    "$NGINX_BIN" -s reload -c "$NGINX_CONF" >/dev/null 2>&1 || true
                fi
            fi
            sleep 2
        done
    ) &
    append_pid "$!"
}

start_log_tail() {
    (
        while :; do
            newest_log="$(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' 2>/dev/null | sort | tail -n 1)"
            if [ -n "$newest_log" ]; then
                exec tail -n +1 -f "$newest_log" 2>/dev/null
            fi
            sleep 1
        done
    ) &
    append_pid "$!"
}

trap on_signal TERM HUP INT

if [ ! -x "$CATEYE_BIN" ]; then
    log "Cateye binary not found at $CATEYE_BIN"
    exit 1
fi
if [ ! -x "$NGINX_BIN" ]; then
    log "Nginx binary not found at $NGINX_BIN"
    exit 1
fi

mkdir -p "$ADDON_DIR" "$LOG_DIR"

if [ ! -f "$CONFIG_PATH" ]; then
    cp "$DEFAULT_CONFIG_PATH" "$CONFIG_PATH"
    log "Initialized default config at $CONFIG_PATH"
fi

log "Using config file at $CONFIG_PATH"
log "Log files will be written under $LOG_DIR"

validate_admin_config
render_nginx_config

"$CATEYE_BIN" client -c "$CONFIG_PATH" &
CATEYE_PID="$!"
append_pid "$CATEYE_PID"

start_nginx
start_config_watcher
start_log_tail

set +e
wait "$CATEYE_PID"
STATUS="$?"
set -e

stop_all
exit "$STATUS"
