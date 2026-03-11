#!/bin/bash
# =============================================================================
# disk-cleanup.sh
# Limpeza automática de disco com suporte a múltiplas partições
# Config: /etc/disk-cleanup.conf
# =============================================================================

CONFIG_FILE="/etc/disk-cleanup.conf"
LOG_FILE="/var/log/disk-cleanup.log"

# ── FUNÇÕES ───────────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SECTION] $1" | tee -a "$LOG_FILE"
}

log_global() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [global] $1" | tee -a "$LOG_FILE"
}

get_usage() {
    local mount="$1"
    df --output=pcent "$mount" 2>/dev/null | tail -1 | tr -d '% '
}

parse_value() {
    echo "$1" | sed 's/^[^=]*=\s*//' | sed 's/\s*#.*//' | xargs
}

cleanup_partition() {
    local target_dir="$1"
    local mount_point="$2"
    local threshold_high="$3"
    local threshold_low="$4"

    if [ ! -d "$target_dir" ]; then
        log "ERRO: Diretório '$target_dir' não encontrado. Pulando."
        return 1
    fi

    if ! df "$mount_point" &>/dev/null; then
        log "ERRO: Ponto de montagem '$mount_point' inválido. Pulando."
        return 1
    fi

    local usage
    usage=$(get_usage "$mount_point")

    log "Uso atual em '$mount_point': ${usage}%  (limite: ${threshold_high}%, alvo: ${threshold_low}%)"

    if [ "$usage" -lt "$threshold_high" ]; then
        log "Dentro do limite. Nada a fazer."
        return 0
    fi

    log "ALERTA: Uso em ${usage}% — iniciando limpeza em '$target_dir'"

    local deleted=0
    local freed=0

    while IFS= read -r -d '' file; do
        usage=$(get_usage "$mount_point")

        if [ "$usage" -le "$threshold_low" ]; then
            log "Uso voltou para ${usage}%. Limpeza concluída."
            break
        fi

        local file_size
        file_size=$(du -b "$file" 2>/dev/null | cut -f1)

        if rm -f "$file"; then
            deleted=$((deleted + 1))
            freed=$((freed + file_size))
            log "Apagado: $file ($(numfmt --to=iec $file_size))"
        else
            log "ERRO ao apagar: $file"
        fi

    done < <(find "$target_dir" -type f -printf '%T+ %p\0' | sort -z | sed -z 's/^[^ ]* //')

    local freed_hr
    freed_hr=$(numfmt --to=iec $freed)
    log "Finalizado: ${deleted} arquivo(s) removido(s), ${freed_hr} liberado(s). Uso final: $(get_usage "$mount_point")%"
}

# ── LEITURA DO CONFIG ─────────────────────────────────────────────────────────

if [ ! -f "$CONFIG_FILE" ]; then
    log_global "ERRO: Arquivo de configuração não encontrado: $CONFIG_FILE"
    exit 1
fi

log_global "Iniciando verificação — lendo $CONFIG_FILE"

SECTION=""
TARGET_DIR=""
MOUNT_POINT=""
THRESHOLD_HIGH=""
THRESHOLD_LOW=""
SECTIONS_FOUND=0

process_section() {
    if [ -n "$SECTION" ] && [ -n "$TARGET_DIR" ] && [ -n "$MOUNT_POINT" ] \
       && [ -n "$THRESHOLD_HIGH" ] && [ -n "$THRESHOLD_LOW" ]; then
        SECTIONS_FOUND=$((SECTIONS_FOUND + 1))
        cleanup_partition "$TARGET_DIR" "$MOUNT_POINT" "$THRESHOLD_HIGH" "$THRESHOLD_LOW"
    elif [ -n "$SECTION" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SECTION] AVISO: Seção incompleta, ignorada." | tee -a "$LOG_FILE"
    fi
}

while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "$line" || "$line" == \#* ]] && continue

    if [[ "$line" =~ ^\[(.+)\]$ ]]; then
        process_section
        SECTION="${BASH_REMATCH[1]}"
        TARGET_DIR=""
        MOUNT_POINT=""
        THRESHOLD_HIGH=""
        THRESHOLD_LOW=""
        continue
    fi

    key=$(echo "$line" | cut -d'=' -f1 | xargs | tr '[:upper:]' '[:lower:]')
    val=$(parse_value "$line")

    case "$key" in
        target_dir)     TARGET_DIR="$val" ;;
        mount_point)    MOUNT_POINT="$val" ;;
        threshold_high) THRESHOLD_HIGH="$val" ;;
        threshold_low)  THRESHOLD_LOW="$val" ;;
    esac

done < "$CONFIG_FILE"

process_section

log_global "Verificação concluída. ${SECTIONS_FOUND} partição(ões) processada(s)."
