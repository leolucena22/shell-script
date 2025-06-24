#!/bin/bash

# =============================================================================
# Script: Limpeza Automática de Logs Antigos
# Descrição: Remove logs antigos e compacta logs recentes para otimizar espaço
# Autor: Sistema de Manutenção
# Data: $(date +%Y-%m-%d)
# =============================================================================

# Configurações
DIAS_REMOVER=30                     # Logs mais antigos que isso serão removidos
DIAS_COMPACTAR=7                    # Logs mais antigos que isso serão compactados
LOG_FILE="/var/log/log_cleanup.log"
HOSTNAME=$(hostname)
ESPACO_MINIMO_GB=5                  # Espaço mínimo necessário em GB

# Diretórios de logs para limpar
DIRETORIOS_LOGS=(
    "/var/log"
    "/var/log/apache2"
    "/var/log/nginx"
    "/var/log/mysql"
    "/var/log/postgresql"
    "/var/log/samba"
    "/home/*/logs"  # Logs de usuários
)

# Padrões de arquivos para diferentes tipos de limpeza
ARQUIVOS_REMOVER=(
    "*.log.*"           # Logs rotacionados antigos
    "*.gz"              # Logs comprimidos antigos
    "*.bz2"             # Logs comprimidos antigos
    "*.old"             # Arquivos .old
    "kern.log.*"        # Logs do kernel antigos
    "syslog.*"          # Syslogs antigos
    "auth.log.*"        # Logs de autenticação antigos
    "mail.log.*"        # Logs de email antigos
    "error.log.*"       # Error logs antigos
    "access.log.*"      # Access logs antigos
)

ARQUIVOS_COMPACTAR=(
    "*.log"             # Logs ativos antigos
    "messages"          # Messages antigos
    "secure"            # Secure logs antigos
    "maillog"           # Mail logs antigos
)

# Arquivos críticos que NUNCA devem ser removidos
ARQUIVOS_PROTEGIDOS=(
    "kern.log"
    "syslog"
    "auth.log"
    "dpkg.log"
    "alternatives.log"
)

# Cores para output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para logging
log_message() {
    local nivel="$1"
    local mensagem="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$nivel] $mensagem" >> "$LOG_FILE"
    
    # Também exibe no terminal se executado manualmente
    if [ -t 1 ]; then
        case $nivel in
            "ERRO")    echo -e "${RED}[$timestamp] [$nivel] $mensagem${NC}" ;;
            "ALERTA")  echo -e "${YELLOW}[$timestamp] [$nivel] $mensagem${NC}" ;;
            "INFO")    echo -e "${GREEN}[$timestamp] [$nivel] $mensagem${NC}" ;;
            "DEBUG")   echo -e "${BLUE}[$timestamp] [$nivel] $mensagem${NC}" ;;
            *)         echo "[$timestamp] [$nivel] $mensagem" ;;
        esac
    fi
}

# Função para verificar espaço em disco
verificar_espaco() {
    local diretorio="$1"
    local espaco_livre_kb=$(df "$diretorio" | tail -1 | awk '{print $4}')
    local espaco_livre_gb=$((espaco_livre_kb / 1024 / 1024))
    echo "$espaco_livre_gb"
}

# Função para formatar bytes em formato legível
formatar_bytes() {
    local bytes="$1"
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$(($bytes/1024))KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$(($bytes/1048576))MB"
    else
        echo "$(($bytes/1073741824))GB"
    fi
}

# Função para verificar se arquivo está protegido
arquivo_protegido() {
    local arquivo="$1"
    local nome_arquivo=$(basename "$arquivo")
    
    for protegido in "${ARQUIVOS_PROTEGIDOS[@]}"; do
        if [[ "$nome_arquivo" == "$protegido" ]]; then
            return 0
        fi
    done
    return 1
}

# Função para compactar arquivo
compactar_arquivo() {
    local arquivo="$1"
    local arquivo_compactado="${arquivo}.gz"
    
    if [ -f "$arquivo" ] && [ ! -f "$arquivo_compactado" ]; then
        if gzip "$arquivo" 2>/dev/null; then
            log_message "INFO" "Arquivo compactado: $arquivo"
            return 0
        else
            log_message "ERRO" "Falha ao compactar: $arquivo"
            return 1
        fi
    fi
    return 1
}

# Função para remover arquivo com segurança
remover_arquivo() {
    local arquivo="$1"
    local tamanho_antes=0
    
    if [ -f "$arquivo" ]; then
        tamanho_antes=$(stat -f%z "$arquivo" 2>/dev/null || stat -c%s "$arquivo" 2>/dev/null || echo "0")
        
        # Garantir que tamanho_antes seja um número
        if ! [[ "$tamanho_antes" =~ ^[0-9]+$ ]]; then
            tamanho_antes=0
        fi
        
        if arquivo_protegido "$arquivo"; then
            log_message "ALERTA" "Arquivo protegido ignorado: $arquivo"
            return 1
        fi
        
        if rm "$arquivo" 2>/dev/null; then
            log_message "INFO" "Arquivo removido: $arquivo ($(formatar_bytes $tamanho_antes))"
            return "$tamanho_antes"
        else
            log_message "ERRO" "Falha ao remover: $arquivo"
            return 0
        fi
    fi
    return 0
}

# Função principal de limpeza
limpar_logs() {
    local total_removido=0
    local total_compactado=0
    local arquivos_removidos=0
    local arquivos_compactados=0
    local relatorio=""
    
    log_message "INFO" "Iniciando limpeza de logs em $HOSTNAME"
    
    # Cabeçalho do relatório
    relatorio="=== RELATÓRIO DE LIMPEZA DE LOGS ===\n"
    relatorio+="Servidor: $HOSTNAME\n"
    relatorio+="Data/Hora: $(date '+%d/%m/%Y %H:%M:%S')\n"
    relatorio+="Critério de Remoção: Arquivos mais antigos que $DIAS_REMOVER dias\n"
    relatorio+="Critério de Compactação: Arquivos mais antigos que $DIAS_COMPACTAR dias\n\n"
    
    # Verificar espaço antes da limpeza
    local espaco_antes=$(verificar_espaco "/var")
    relatorio+="Espaço livre antes: ${espaco_antes}GB\n\n"
    
    # Processar cada diretório
    for diretorio in "${DIRETORIOS_LOGS[@]}"; do
        # Expandir wildcards (para /home/*/logs)
        for dir_expandido in $diretorio; do
            if [ -d "$dir_expandido" ]; then
                log_message "INFO" "Processando diretório: $dir_expandido"
                relatorio+="📁 Diretório: $dir_expandido\n"
                
                local removidos_dir=0
                local compactados_dir=0
                local bytes_removidos_dir=0
                
                # Remover arquivos antigos
                for padrao in "${ARQUIVOS_REMOVER[@]}"; do
                    while IFS= read -r -d '' arquivo; do
                        if [ -f "$arquivo" ]; then
                            # Verificar idade do arquivo
                            local idade_arquivo=$(find "$arquivo" -mtime +$DIAS_REMOVER -print 2>/dev/null)
                            if [ -n "$idade_arquivo" ]; then
                                local bytes_arquivo=$(remover_arquivo "$arquivo")
                                if [[ "$bytes_arquivo" =~ ^[0-9]+$ ]] && [ "$bytes_arquivo" -gt 0 ]; then
                                    removidos_dir=$((removidos_dir + 1))
                                    bytes_removidos_dir=$((bytes_removidos_dir + bytes_arquivo))
                                fi
                            fi
                        fi
                    done < <(find "$dir_expandido" -maxdepth 2 -name "$padrao" -type f -print0 2>/dev/null)
                done
                
                # Compactar arquivos recentes mas não muito novos
                for padrao in "${ARQUIVOS_COMPACTAR[@]}"; do
                    while IFS= read -r -d '' arquivo; do
                        if [ -f "$arquivo" ]; then
                            # Verificar se arquivo tem idade entre DIAS_COMPACTAR e DIAS_REMOVER
                            local arquivo_compactar=$(find "$arquivo" -mtime +$DIAS_COMPACTAR -mtime -$DIAS_REMOVER -print 2>/dev/null)
                            if [ -n "$arquivo_compactar" ] && [[ "$arquivo" != *.gz ]] && [[ "$arquivo" != *.bz2 ]]; then
                                if compactar_arquivo "$arquivo"; then
                                    compactados_dir=$((compactados_dir + 1))
                                fi
                            fi
                        fi
                    done < <(find "$dir_expandido" -maxdepth 2 -name "$padrao" -type f -print0 2>/dev/null)
                done
                
                # Atualizar totais
                arquivos_removidos=$((arquivos_removidos + removidos_dir))
                arquivos_compactados=$((arquivos_compactados + compactados_dir))
                total_removido=$((total_removido + bytes_removidos_dir))
                
                # Adicionar ao relatório
                relatorio+="  ├─ Arquivos removidos: $removidos_dir\n"
                relatorio+="  ├─ Arquivos compactados: $compactados_dir\n"
                relatorio+="  └─ Espaço liberado: $(formatar_bytes $bytes_removidos_dir)\n\n"
                
            else
                log_message "DEBUG" "Diretório não encontrado: $dir_expandido"
            fi
        done
    done
    
    # Limpeza especial para logs do sistema
    limpar_logs_sistema
    
    # Verificar espaço após limpeza
    local espaco_depois=$(verificar_espaco "/var")
    local espaco_liberado=$((espaco_depois - espaco_antes))
    
    # Completar relatório
    relatorio+="=== RESUMO FINAL ===\n"
    relatorio+="Total de arquivos removidos: $arquivos_removidos\n"
    relatorio+="Total de arquivos compactados: $arquivos_compactados\n"
    relatorio+="Espaço total liberado: $(formatar_bytes $total_removido)\n"
    relatorio+="Espaço livre antes: ${espaco_antes}GB\n"
    relatorio+="Espaço livre depois: ${espaco_depois}GB\n"
    
    if [ "$espaco_liberado" -gt 0 ]; then
        relatorio+="✅ Espaço adicional liberado: ${espaco_liberado}GB\n"
    fi
    
    # Verificar se ainda há espaço suficiente
    if [ "$espaco_depois" -lt "$ESPACO_MINIMO_GB" ]; then
        relatorio+="⚠️  ALERTA: Espaço livre ainda abaixo do mínimo recomendado (${ESPACO_MINIMO_GB}GB)\n"
        log_message "ALERTA" "Espaço livre insuficiente: ${espaco_depois}GB (mínimo: ${ESPACO_MINIMO_GB}GB)"
    fi
    
    # Log do resumo
    log_message "INFO" "Limpeza concluída. Removidos: $arquivos_removidos, Compactados: $arquivos_compactados, Liberado: $(formatar_bytes $total_removido)"
    
    # Se executado manualmente, mostra o relatório
    if [ -t 1 ]; then
        echo -e "\n$relatorio"
    fi
}

# Função para limpeza especial de logs do sistema
limpar_logs_sistema() {
    log_message "INFO" "Executando limpeza especial de logs do sistema"
    
    # Limpar logs do journal (systemd)
    if command -v journalctl &> /dev/null; then
        # Manter apenas logs dos últimos 30 dias
        journalctl --vacuum-time=30d >/dev/null 2>&1
        # Limitar tamanho máximo para 500MB
        journalctl --vacuum-size=500M >/dev/null 2>&1
        log_message "INFO" "Logs do systemd journal limpos"
    fi
    
    # Limpar cache do apt
    if command -v apt-get &> /dev/null; then
        apt-get clean >/dev/null 2>&1
        log_message "INFO" "Cache do APT limpo"
    fi
    
    # Limpar logs vazios
    find /var/log -type f -empty -name "*.log" -delete 2>/dev/null
    log_message "INFO" "Logs vazios removidos"
    
    # Limpar core dumps antigos
    find /var/crash -type f -mtime +$DIAS_REMOVER -delete 2>/dev/null
    find /tmp -name "core.*" -mtime +7 -delete 2>/dev/null
    log_message "INFO" "Core dumps antigos removidos"
}

# Função para criar backup de configurações importantes
backup_configs() {
    local backup_dir="/var/backups/log-cleanup"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir" 2>/dev/null
    
    # Backup de logrotate configs
    if [ -d "/etc/logrotate.d" ]; then
        tar -czf "$backup_dir/logrotate_configs_$timestamp.tar.gz" /etc/logrotate.d/ >/dev/null 2>&1
        log_message "INFO" "Backup de configurações do logrotate criado"
    fi
    
    # Manter apenas os últimos 5 backups
    find "$backup_dir" -name "logrotate_configs_*.tar.gz" -mtime +30 -delete 2>/dev/null
}

# Função para criar diretório de log se não existir
criar_log_dir() {
    local log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
        log_message "INFO" "Diretório de log criado: $log_dir"
    fi
}

# Função para rotacionar o próprio log do script
rotacionar_log_proprio() {
    if [ -f "$LOG_FILE" ]; then
        local tamanho_log=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
        
        # Garantir que seja um número
        if ! [[ "$tamanho_log" =~ ^[0-9]+$ ]]; then
            tamanho_log=0
        fi
        
        if [ "$tamanho_log" -gt 5242880 ]; then
            mv "$LOG_FILE" "${LOG_FILE}.old"
            log_message "INFO" "Log do script rotacionado"
        fi
    fi
}

# Função de ajuda
mostrar_ajuda() {
    echo "Uso: $0 [opção]"
    echo ""
    echo "Opções:"
    echo "  -h, --help       Mostra esta ajuda"
    echo "  -t, --test       Executa em modo teste (sem remover arquivos)"
    echo "  -c, --config     Mostra configuração atual"
    echo "  -l, --log        Mostra últimas 20 linhas do log"
    echo "  -s, --stats      Mostra estatísticas de uso de disco"
    echo "  -b, --backup     Cria backup das configurações"
    echo ""
    echo "Para uso no cron, execute sem parâmetros."
}

# Função para mostrar configuração
mostrar_config() {
    echo "=== CONFIGURAÇÃO ATUAL ==="
    echo "Dias para remoção: $DIAS_REMOVER"
    echo "Dias para compactação: $DIAS_COMPACTAR"
    echo "Arquivo de Log: $LOG_FILE"
    echo "Espaço mínimo: ${ESPACO_MINIMO_GB}GB"
    echo ""
    echo "Diretórios monitorados:"
    for dir in "${DIRETORIOS_LOGS[@]}"; do
        echo "  - $dir"
    done
}

# Função para mostrar estatísticas
mostrar_stats() {
    echo "=== ESTATÍSTICAS DE USO DE DISCO ==="
    echo ""
    for diretorio in "${DIRETORIOS_LOGS[@]}"; do
        for dir_expandido in $diretorio; do
            if [ -d "$dir_expandido" ]; then
                echo "📁 $dir_expandido:"
                du -sh "$dir_expandido" 2>/dev/null | awk '{print "  Tamanho total: " $1}'
                find "$dir_expandido" -name "*.log*" -type f -mtime +$DIAS_REMOVER 2>/dev/null | wc -l | awk '{print "  Logs para remoção: " $1}'
                find "$dir_expandido" -name "*.log" -type f -mtime +$DIAS_COMPACTAR -mtime -$DIAS_REMOVER 2>/dev/null | wc -l | awk '{print "  Logs para compactação: " $1}'
                echo ""
            fi
        done
    done
}

# Main
main() {
    case "${1:-}" in
        -h|--help)
            mostrar_ajuda
            exit 0
            ;;
        -c|--config)
            mostrar_config
            exit 0
            ;;
        -l|--log)
            if [ -f "$LOG_FILE" ]; then
                tail -20 "$LOG_FILE"
            else
                echo "Arquivo de log não encontrado: $LOG_FILE"
            fi
            exit 0
            ;;
        -s|--stats)
            mostrar_stats
            exit 0
            ;;
        -b|--backup)
            criar_log_dir
            backup_configs
            echo "Backup das configurações criado"
            exit 0
            ;;
        -t|--test)
            echo "=== MODO TESTE - NENHUM ARQUIVO SERÁ REMOVIDO ==="
            echo "Esta funcionalidade mostraria quais arquivos seriam afetados"
            echo "Implementação do modo teste pendente"
            exit 0
            ;;
        "")
            # Execução normal (cron)
            ;;
        *)
            echo "Opção inválida: $1"
            mostrar_ajuda
            exit 1
            ;;
    esac
    
    # Executa a limpeza
    criar_log_dir
    rotacionar_log_proprio
    backup_configs
    limpar_logs
}

# Executa o script
main "$@"
