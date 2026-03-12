#!/bin/bash
# =============================================================================
# install.sh — Instalador do disk-cleanup
# Uso via curl:
#   curl -sSL https://raw.githubusercontent.com/SEU_USER/disk-cleanup/main/install.sh | sudo bash
# =============================================================================

set -e

# ── REPOSITÓRIO ───────────────────────────────────────────────────────────────
GITHUB_USER="marcosendler"
GITHUB_REPO="disk-cleanup"
GITHUB_BRANCH="master"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"

# ── CORES ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── CAMINHOS DE DESTINO ───────────────────────────────────────────────────────
SCRIPT_DEST="/usr/local/bin/disk-cleanup.sh"
CONF_DEST="/etc/disk-cleanup.conf"
SERVICE_DEST="/etc/systemd/system/disk-cleanup.service"
TIMER_DEST="/etc/systemd/system/disk-cleanup.timer"
LOG_FILE="/var/log/disk-cleanup.log"

# ── FUNÇÕES ───────────────────────────────────────────────────────────────────

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║        disk-cleanup — Instalador         ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

ok()   { echo -e "  ${GREEN}✔${NC}  $1"; }
info() { echo -e "  ${CYAN}→${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}   $1"; }
err()  { echo -e "  ${RED}✘${NC}  $1"; }
step() { echo -e "\n${BOLD}${BLUE}▸ $1${NC}"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Este script precisa ser executado como root."
        echo ""
        echo "    Execute com sudo:"
        echo -e "    ${CYAN}curl -sSL ${BASE_URL}/install.sh | sudo bash${NC}"
        exit 1
    fi
}

check_deps() {
    step "Verificando dependências"
    for cmd in curl systemctl df find numfmt; do
        if command -v "$cmd" &>/dev/null; then
            ok "$cmd encontrado"
        else
            err "$cmd não encontrado — instale antes de continuar."
            exit 1
        fi
    done
}

confirm() {
    local msg="$1"
    local default="${2:-s}"
    local prompt
    [ "$default" = "s" ] && prompt="[S/n]" || prompt="[s/N]"
    # Se estiver rodando via pipe (curl | bash), não tem TTY — assume default
    if [ ! -t 0 ]; then
        echo -e "  ${YELLOW}?${NC}  $msg $prompt → ${default} (modo não-interativo)"
        [[ "$default" =~ ^[Ss]$ ]]
        return
    fi
    echo -ne "  ${YELLOW}?${NC}  $msg $prompt "
    read -r answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Ss]$ ]]
}

download() {
    local url="$1"
    local dest="$2"
    local label="$3"

    if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
        ok "Baixado: $label"
    else
        err "Falha ao baixar: $url"
        err "Verifique o usuário/repositório no topo do script."
        exit 1
    fi
}

download_files() {
    step "Baixando arquivos de ${CYAN}github.com/${GITHUB_USER}/${GITHUB_REPO}${NC}"

    # Script principal (sempre sobrescreve)
    download "${BASE_URL}/disk-cleanup.sh"      "$SCRIPT_DEST"  "disk-cleanup.sh"
    chmod +x "$SCRIPT_DEST"

    # Config: só baixa se não existir, para não apagar partições já configuradas
    if [ -f "$CONF_DEST" ]; then
        warn "Configuração já existe em $CONF_DEST"
        if confirm "Sobrescrever? (suas partições configuradas serão perdidas)"; then
            download "${BASE_URL}/disk-cleanup.conf" "$CONF_DEST" "disk-cleanup.conf"
        else
            info "Configuração mantida sem alteração."
        fi
    else
        download "${BASE_URL}/disk-cleanup.conf"    "$CONF_DEST"    "disk-cleanup.conf"
    fi

    # Systemd units (sempre sobrescreve)
    download "${BASE_URL}/disk-cleanup.service" "$SERVICE_DEST" "disk-cleanup.service"
    download "${BASE_URL}/disk-cleanup.timer"   "$TIMER_DEST"   "disk-cleanup.timer"

    # Log
    touch "$LOG_FILE"
    ok "Arquivo de log: $LOG_FILE"
}

configure_timer() {
    step "Configurando intervalo do timer"
    echo ""
    echo -e "  Intervalo padrão: ${BOLD}15 minutos${NC}"
    if [ -t 0 ] && confirm "Deseja alterar o intervalo?"; then
        echo -ne "  ${YELLOW}?${NC}  Novo intervalo (ex: 5min, 30min, 1h, 2h): "
        read -r interval
        if [ -n "$interval" ]; then
            sed -i "s/OnUnitActiveSec=.*/OnUnitActiveSec=${interval}/" "$TIMER_DEST"
            ok "Intervalo definido para: $interval"
        else
            info "Intervalo mantido em 15 minutos."
        fi
    else
        info "Intervalo mantido em 15 minutos."
    fi
}

enable_service() {
    step "Ativando serviço systemd"
    systemctl daemon-reload
    ok "daemon-reload executado"
    systemctl enable disk-cleanup.timer
    ok "Timer habilitado no boot"
    systemctl start disk-cleanup.timer
    ok "Timer iniciado"
}

run_now() {
    step "Execução imediata"
    if confirm "Deseja executar o script agora para testar?"; then
        echo ""
        systemctl start disk-cleanup.service
        echo ""
        info "Saída do log:"
        echo -e "  ${BLUE}────────────────────────────────────────────${NC}"
        tail -20 "$LOG_FILE" | sed 's/^/  /'
        echo -e "  ${BLUE}────────────────────────────────────────────${NC}"
    fi
}

print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║         Instalação concluída! ✔          ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Próximos passos:${NC}"
    echo ""
    echo -e "  1. Edite as partições monitoradas:"
    echo -e "     ${CYAN}nano /etc/disk-cleanup.conf${NC}"
    echo ""
    echo -e "  2. Acompanhe os logs:"
    echo -e "     ${CYAN}tail -f /var/log/disk-cleanup.log${NC}"
    echo ""
    echo -e "  3. Status do timer:"
    echo -e "     ${CYAN}systemctl status disk-cleanup.timer${NC}"
    echo ""
    echo -e "  4. Executar manualmente:"
    echo -e "     ${CYAN}sudo systemctl start disk-cleanup.service${NC}"
    echo ""
    echo -e "  5. Desinstalar:"
    echo -e "     ${CYAN}curl -sSL ${BASE_URL}/install.sh | sudo bash -s -- --uninstall${NC}"
    echo ""
}

uninstall() {
    echo ""
    warn "Modo desinstalação"
    if confirm "Tem certeza que deseja remover o disk-cleanup?" "n"; then
        systemctl stop disk-cleanup.timer    2>/dev/null || true
        systemctl disable disk-cleanup.timer 2>/dev/null || true
        rm -f "$SCRIPT_DEST" "$SERVICE_DEST" "$TIMER_DEST"
        systemctl daemon-reload
        ok "disk-cleanup removido."
        if confirm "Remover também a configuração ($CONF_DEST)?"; then
            rm -f "$CONF_DEST"
            ok "Configuração removida."
        fi
        if confirm "Remover também o log ($LOG_FILE)?"; then
            rm -f "$LOG_FILE"
            ok "Log removido."
        fi
    else
        info "Desinstalação cancelada."
    fi
    exit 0
}

# ── MAIN ──────────────────────────────────────────────────────────────────────

print_header
check_root

[ "${1}" = "--uninstall" ] && uninstall

check_deps
download_files
configure_timer
enable_service
run_now
print_summary
