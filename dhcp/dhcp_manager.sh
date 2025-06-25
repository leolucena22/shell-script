#!/bin/bash

# Script de Gerenciamento do Servidor DHCP
# Autor: Sistema de Administração de Rede
# Data: $(date)

# Configurações globais
DHCP_CONFIG_FILE="/etc/dhcp/dhcpd.conf"
DHCP_CONFIG_BACKUP="/etc/dhcp/dhcpd.conf.backup"
RESERVAS_FILE="/opt/dhcp/RESERVA.txt"
DHCP_SERVICE="isc-dhcp-server"
LOG_FILE="/var/log/dhcp_manager.log"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Função para exibir mensagens coloridas
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Função para verificar se o script está sendo executado como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_message $RED "Este script deve ser executado como root!"
        exit 1
    fi
}

# Função para criar diretórios necessários
setup_directories() {
    mkdir -p /opt/dhcp
    mkdir -p /var/log

    # Criar arquivo de reservas se não existir
    if [[ ! -f "$RESERVAS_FILE" ]]; then
        cat > "$RESERVAS_FILE" << EOF
Diretoria,00:05:84:AB:EE:FF,192.168.0.1
Secretaria,00:05:84:EE:2B:45,192.168.0.2
Tesouraria,00:05:84:4E:CB:47,192.168.0.3
Producao,00:05:84:2B:2A:A4,192.168.0.4
Guarita,00:05:84:EF:12:20,192.168.0.49
EOF
        print_message $GREEN "Arquivo de reservas criado em: $RESERVAS_FILE"
    fi
}

# Função para validar endereço MAC
validate_mac() {
    local mac=$1
    if [[ $mac =~ ^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$ ]]; then
        return 0
    else
        return 1
    fi
}

# Função para validar endereço IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Função para criar backup do arquivo de configuração
create_backup() {
    if [[ -f "$DHCP_CONFIG_FILE" ]]; then
        cp "$DHCP_CONFIG_FILE" "${DHCP_CONFIG_BACKUP}.$(date +%Y%m%d_%H%M%S)"
        print_message $GREEN "Backup criado com sucesso!"
        log_message "Backup do arquivo DHCP criado"
    fi
}

# Função para gerar arquivo de configuração DHCP
generate_dhcp_config() {
    local subnet_range_start=${1:-"192.168.0.100"}
    local subnet_range_end=${2:-"192.168.0.149"}

    print_message $BLUE "Gerando arquivo de configuração DHCP..."

    cat > "$DHCP_CONFIG_FILE" << EOF
# Configuração do Servidor DHCP
# Gerado automaticamente em $(date)

# Configurações globais
default-lease-time 600;
max-lease-time 7200;
authoritative;

# Configuração da subnet
subnet 192.168.0.0 netmask 255.255.255.0 {
    range $subnet_range_start $subnet_range_end;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    option domain-name "local.domain";
    option routers 192.168.0.1;
    option broadcast-address 192.168.0.255;
}

# Reservas de IP (hosts estáticos)
EOF

    # Adicionar reservas do arquivo
    if [[ -f "$RESERVAS_FILE" ]]; then
        while IFS=',' read -r nome mac ip; do
            # Remover espaços em branco
            nome=$(echo "$nome" | tr -d ' ')
            mac=$(echo "$mac" | tr -d ' ')
            ip=$(echo "$ip" | tr -d ' ')

            if [[ -n "$nome" && -n "$mac" && -n "$ip" ]]; then
                cat >> "$DHCP_CONFIG_FILE" << EOF

host $nome {
    hardware ethernet $mac;
    fixed-address $ip;
}
EOF
            fi
        done < "$RESERVAS_FILE"
    fi

    print_message $GREEN "Arquivo de configuração DHCP gerado com sucesso!"
    log_message "Arquivo de configuração DHCP gerado"
}

# Função para atualizar faixa de IP
update_ip_range() {
    print_message $YELLOW "=== ATUALIZAR FAIXA DE IP DO DHCP ==="
    echo -n "Digite o IP inicial da faixa (atual: 192.168.0.100): "
    read ip_start
    [[ -z "$ip_start" ]] && ip_start="192.168.0.100"

    echo -n "Digite o IP final da faixa (atual: 192.168.0.149): "
    read ip_end
    [[ -z "$ip_end" ]] && ip_end="192.168.0.149"

    if validate_ip "$ip_start" && validate_ip "$ip_end"; then
        create_backup
        generate_dhcp_config "$ip_start" "$ip_end"
        print_message $GREEN "Faixa de IP atualizada com sucesso!"
    else
        print_message $RED "Endereços IP inválidos!"
    fi
}

# Função para adicionar nova reserva
add_reservation() {
    print_message $YELLOW "=== ADICIONAR NOVA RESERVA ==="

    echo -n "Nome do computador: "
    read nome

    echo -n "Endereço MAC (formato: XX:XX:XX:XX:XX:XX): "
    read mac

    echo -n "Endereço IP: "
    read ip

    # Validações
    if [[ -z "$nome" ]]; then
        print_message $RED "Nome não pode estar vazio!"
        return 1
    fi

    if ! validate_mac "$mac"; then
        print_message $RED "Endereço MAC inválido!"
        return 1
    fi

    if ! validate_ip "$ip"; then
        print_message $RED "Endereço IP inválido!"
        return 1
    fi

    # Verificar se MAC ou IP já existem
    if grep -q "$mac\|$ip" "$RESERVAS_FILE" 2>/dev/null; then
        print_message $RED "MAC ou IP já existe nas reservas!"
        return 1
    fi

    # Adicionar ao arquivo de reservas
    echo "$nome,$mac,$ip" >> "$RESERVAS_FILE"
    print_message $GREEN "Reserva adicionada com sucesso!"

    # Perguntar se quer atualizar a configuração
    echo -n "Deseja atualizar a configuração do DHCP agora? (s/n): "
    read update_now
    if [[ "$update_now" =~ ^[sS]$ ]]; then
        create_backup
        generate_dhcp_config
        restart_dhcp
    fi

    log_message "Nova reserva adicionada: $nome,$mac,$ip"
}

# Função para listar reservas existentes
list_reservations() {
    print_message $YELLOW "=== RESERVAS EXISTENTES ==="

    if [[ ! -f "$RESERVAS_FILE" ]]; then
        print_message $RED "Arquivo de reservas não encontrado!"
        return 1
    fi

    printf "%-15s %-20s %-15s\n" "NOME" "MAC ADDRESS" "IP ADDRESS"
    printf "%-15s %-20s %-15s\n" "----" "-----------" "----------"

    while IFS=',' read -r nome mac ip; do
        # Remover espaços em branco
        nome=$(echo "$nome" | tr -d ' ')
        mac=$(echo "$mac" | tr -d ' ')
        ip=$(echo "$ip" | tr -d ' ')

        if [[ -n "$nome" && -n "$mac" && -n "$ip" ]]; then
            printf "%-15s %-20s %-15s\n" "$nome" "$mac" "$ip"
        fi
    done < "$RESERVAS_FILE"
}

# Função para iniciar o servidor DHCP
start_dhcp() {
    print_message $BLUE "Iniciando servidor DHCP..."

    # Verificar se a configuração existe
    if [[ ! -f "$DHCP_CONFIG_FILE" ]]; then
        print_message $YELLOW "Arquivo de configuração não encontrado. Gerando..."
        generate_dhcp_config
    fi

    # Testar configuração
    if dhcpd -t -cf "$DHCP_CONFIG_FILE" 2>/dev/null; then
        systemctl start "$DHCP_SERVICE"
        if systemctl is-active --quiet "$DHCP_SERVICE"; then
            print_message $GREEN "Servidor DHCP iniciado com sucesso!"
            log_message "Servidor DHCP iniciado"
        else
            print_message $RED "Falha ao iniciar o servidor DHCP!"
            log_message "Falha ao iniciar servidor DHCP"
        fi
    else
        print_message $RED "Erro na configuração do DHCP!"
        log_message "Erro na configuração do DHCP"
    fi
}

# Função para parar o servidor DHCP
stop_dhcp() {
    print_message $BLUE "Parando servidor DHCP..."
    systemctl stop "$DHCP_SERVICE"

    if ! systemctl is-active --quiet "$DHCP_SERVICE"; then
        print_message $GREEN "Servidor DHCP parado com sucesso!"
        log_message "Servidor DHCP parado"
    else
        print_message $RED "Falha ao parar o servidor DHCP!"
        log_message "Falha ao parar servidor DHCP"
    fi
}

# Função para reiniciar o servidor DHCP
restart_dhcp() {
    print_message $BLUE "Reiniciando servidor DHCP..."
    stop_dhcp
    sleep 2
    start_dhcp
}

# Função para verificar status do DHCP
check_dhcp_status() {
    if systemctl is-active --quiet "$DHCP_SERVICE"; then
        print_message $GREEN "Servidor DHCP está ATIVO"
    else
        print_message $RED "Servidor DHCP está INATIVO"
    fi
}

# Função para configurar backup automático via CRON
setup_cron_backup() {
    print_message $BLUE "Configurando backup automático via CRON..."

    # Script de backup
    cat > /opt/dhcp/backup_dhcp.sh << 'EOF'
#!/bin/bash
# Script de backup automático do DHCP
BACKUP_DIR="/opt/dhcp/backups"
mkdir -p "$BACKUP_DIR"

if [[ -f "/etc/dhcp/dhcpd.conf" ]]; then
    cp "/etc/dhcp/dhcpd.conf" "$BACKUP_DIR/dhcpd.conf.$(date +%Y%m%d_%H%M%S)"

    # Manter apenas os últimos 30 backups
    ls -t "$BACKUP_DIR"/dhcpd.conf.* | tail -n +31 | xargs -r rm

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup automático do DHCP realizado" >> /var/log/dhcp_manager.log
fi
EOF

    chmod +x /opt/dhcp/backup_dhcp.sh

    # Adicionar ao crontab (backup diário às 02:00)
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/dhcp/backup_dhcp.sh") | crontab -

    print_message $GREEN "Backup automático configurado! (Execução diária às 02:00)"
    log_message "Backup automático via CRON configurado"
}

# Função de inicialização no boot
setup_boot_script() {
    print_message $BLUE "Configurando script de inicialização no boot..."

    cat > /etc/systemd/system/dhcp-autostart.service << EOF
[Unit]
Description=DHCP Auto Configuration Service
After=network.target

[Service]
Type=oneshot
ExecStart=$0 --boot-init
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable dhcp-autostart.service

    print_message $GREEN "Serviço de inicialização automática configurado!"
    log_message "Serviço de inicialização automática configurado"
}

# Função de inicialização no boot (sem interação)
boot_initialization() {
    log_message "Inicialização automática do sistema iniciada"
    setup_directories
    create_backup
    generate_dhcp_config
    start_dhcp
    log_message "Inicialização automática do sistema concluída"
}

# Menu principal
show_menu() {
    clear
    print_message $BLUE "=================================="
    print_message $BLUE "   GERENCIADOR DE SERVIDOR DHCP   "
    print_message $BLUE "=================================="
    echo
    check_dhcp_status
    echo
    print_message $YELLOW "1) Atualizar faixa de IP do DHCP"
    print_message $YELLOW "2) Acrescentar máquina com reserva de IP"
    print_message $YELLOW "3) Listar as reservas existentes"
    print_message $YELLOW "4) START - Iniciar servidor DHCP"
    print_message $YELLOW "5) STOP - Parar servidor DHCP"
    print_message $YELLOW "6) RESTART - Reiniciar servidor DHCP"
    print_message $YELLOW "7) Configurar backup automático (CRON)"
    print_message $YELLOW "8) Configurar inicialização automática"
    print_message $YELLOW "9) SAIR"
    echo
    print_message $GREEN "Digite sua opção: "
}

# Função principal
main() {
    check_root
    setup_directories

    # Verificar se foi chamado para inicialização no boot
    if [[ "$1" == "--boot-init" ]]; then
        boot_initialization
        exit 0
    fi

    while true; do
        show_menu
        read -r option

        case $option in
            1)
                update_ip_range
                read -p "Pressione ENTER para continuar..."
                ;;
            2)
                add_reservation
                read -p "Pressione ENTER para continuar..."
                ;;
            3)
                list_reservations
                read -p "Pressione ENTER para continuar..."
                ;;
            4)
                start_dhcp
                read -p "Pressione ENTER para continuar..."
                ;;
            5)
                stop_dhcp
                read -p "Pressione ENTER para continuar..."
                ;;
            6)
                restart_dhcp
                read -p "Pressione ENTER para continuar..."
                ;;
            7)
                setup_cron_backup
                read -p "Pressione ENTER para continuar..."
                ;;
            8)
                setup_boot_script
                read -p "Pressione ENTER para continuar..."
                ;;
            9)
                print_message $GREEN "Saindo do sistema..."
                log_message "Sistema encerrado pelo usuário"
                exit 0
                ;;
            *)
                print_message $RED "Opção inválida!"
                read -p "Pressione ENTER para continuar..."
                ;;
        esac
    done
}

# Executar função principal
main "$@"
