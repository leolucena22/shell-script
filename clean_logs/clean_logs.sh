#!/bin/bash
# Autor: Leonardo Lucena
# Script Simples de Limpeza de Logs
# Remove logs antigos para liberar espaço em disco

# Cores para saída
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configurações básicas
DIAS_ANTIGOS=30
LOG_FILE="/var/log/cleanup.log"

# Diretórios para limpar
DIRETORIOS=(
    "/var/log"
    "/var/log/apache2"
    "/var/log/nginx"
)

# Função para log
log() {
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo "$timestamp $1" >> "$LOG_FILE"

    # Saída colorida no terminal
    if [[ "$1" == *"Iniciando"* ]] || [[ "$1" == *"concluída"* ]]; then
        echo -e "${GREEN}$timestamp $1${NC}"
    elif [[ "$1" == *"Limpando"* ]]; then
        echo -e "${BLUE}$timestamp $1${NC}"
    elif [[ "$1" == *"limpos"* ]] || [[ "$1" == *"limpo"* ]]; then
        echo -e "${CYAN}$timestamp $1${NC}"
    else
        echo -e "${YELLOW}$timestamp $1${NC}"
    fi
}

# Função para mostrar tamanho em formato legível
tamanho_legivel() {
    local bytes=$1
    if [ $bytes -lt 1048576 ]; then
        echo "$(($bytes/1024))KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(($bytes/1048576))MB"
    else
        echo "$(($bytes/1073741824))GB"
    fi
}

# Função principal de limpeza
limpar_logs() {
    local total_removido=0
    local arquivos_removidos=0

    log "Iniciando limpeza de logs - removendo arquivos com mais de $DIAS_ANTIGOS dias"

    for diretorio in "${DIRETORIOS[@]}"; do
        if [ -d "$diretorio" ]; then
            log "Limpando diretório: $diretorio"

            # Remove logs antigos comprimidos
            find "$diretorio" -name "*.log.*" -type f -mtime +$DIAS_ANTIGOS -exec rm -f {} \; 2>/dev/null
            find "$diretorio" -name "*.gz" -type f -mtime +$DIAS_ANTIGOS -exec rm -f {} \; 2>/dev/null

            # Conta arquivos removidos
            local removidos=$(find "$diretorio" -name "*.log.*" -o -name "*.gz" -type f -mtime +$DIAS_ANTIGOS 2>/dev/null | wc -l)
            arquivos_removidos=$((arquivos_removidos + removidos))
        fi
    done

    # Limpa journal do systemd (últimos 15 dias)
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-time=15d >/dev/null 2>&1
        log "Logs do systemd limpos"
    fi

    # Limpa cache do apt
    if command -v apt-get >/dev/null 2>&1; then
        apt-get clean >/dev/null 2>&1
        log "Cache do APT limpo"
    fi

    # Remove logs vazios
    find /var/log -type f -empty -name "*.log" -delete 2>/dev/null

    log "Limpeza concluída - arquivos processados: $arquivos_removidos"
}

# Função para mostrar espaço em disco
mostrar_espaco() {
    echo -e "${PURPLE}📊 Espaço livre em /var:${NC}"
    df -h /var | tail -1 | awk -v green="$GREEN" -v yellow="$YELLOW" -v nc="$NC" '{
        if ($5+0 > 80) color=yellow; else color=green;
        print "  " color $4 " disponível (" $5 " usado)" nc
    }'
    echo
}

# Função de help
ajuda() {
    echo -e "${CYAN}📋 Uso: $0 [opção]${NC}"
    echo
    echo -e "${YELLOW}Opções:${NC}"
    echo -e "  ${GREEN}-h${NC}    Mostra esta ajuda"
    echo -e "  ${GREEN}-s${NC}    Mostra espaço em disco"
    echo -e "  ${GREEN}-l${NC}    Mostra últimas linhas do log"
    echo
    echo -e "${BLUE}Sem opções: executa a limpeza${NC}"
}

# Processamento dos argumentos
case "${1:-}" in
    -h)
        ajuda
        exit 0
        ;;
    -s)
        mostrar_espaco
        exit 0
        ;;
    -l)
        if [ -f "$LOG_FILE" ]; then
            echo -e "${CYAN}📄 Últimas 10 linhas do log:${NC}"
            tail -10 "$LOG_FILE"
        else
            echo -e "${RED}❌ Log não encontrado: $LOG_FILE${NC}"
        fi
        exit 0
        ;;
    "")
        # Execução normal
        ;;
    *)
        echo -e "${RED}❌ Opção inválida: $1${NC}"
        ajuda
        exit 1
        ;;
esac

# Executa a limpeza
echo -e "${PURPLE}🚀 Iniciando Script de Limpeza de Logs${NC}"
echo -e "${PURPLE}👤 Autor: Leonardo Lucena${NC}"
echo
mostrar_espaco
limpar_logs
mostrar_espaco
echo -e "${GREEN}✅ Script finalizado com sucesso!${NC}"
