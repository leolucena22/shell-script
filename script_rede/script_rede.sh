#!/bin/bash

# Script robusto para gerenciamento de configurações de rede
CONFIG_FILE="/etc/network/interfaces"
INTERFACE="enp0s3"
BACKUP_FILE="/etc/network/interfaces.bak"
TEST_TIMEOUT=15  # Tempo em segundos para testar conexão
PING_TARGET="8.8.8.8"  # Alvo para teste de ping

# Cores para mensagens
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificar root
[ "$(id -u)" -ne 0 ] && echo -e "${RED}ERRO: Execute como root ou com sudo!${NC}" && exit 1

# Verificar interface
if ! ip link show $INTERFACE >/dev/null 2>&1; then
    echo -e "${RED}ERRO: Interface $INTERFACE não encontrada!${NC}"
    echo -e "Interfaces disponíveis:"
    ip -o link show | awk -F': ' '{print $2}'
    exit 1
fi

# Função para testar conexão com timeout
test_connection() {
    echo -n -e "${YELLOW}Testando conexão (timeout: ${TEST_TIMEOUT}s)...${NC} "
    
    # Testa se a interface tem um IP válido
    if ! ip addr show $INTERFACE | grep -q 'inet '; then
        echo -e "${RED}FALHA: Interface sem endereço IP!${NC}"
        return 1
    fi

    # Testa gateway primeiro
    local gateway=$(ip route | grep default | awk '{print $3}')
    if [ -n "$gateway" ]; then
        if ! timeout 3 ping -c 1 -W 1 $gateway >/dev/null 2>&1; then
            echo -e "${RED}FALHA: Não conseguiu alcançar o gateway ($gateway)${NC}"
            return 1
        fi
    fi

    # Testa conectividade com timeout
    if timeout $TEST_TIMEOUT ping -c 3 -W 1 $PING_TARGET >/dev/null 2>&1; then
        echo -e "${GREEN}OK - Conexão ativa${NC}"
        return 0
    else
        echo -e "${RED}FALHA - Sem conexão com a internet${NC}"
        return 1
    fi
}

# Função para configurar rede estática
configure_static() {
    local config_type=$1 address=$2 netmask=$3 gateway=$4 dns1=$5 dns2=$6
    
    echo -e "\n${YELLOW}Configurando rede $config_type (IP Estático)...${NC}"
    create_backup
    
    cat > $CONFIG_FILE <<EOF
# Configuração gerada automaticamente
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto $INTERFACE
iface $INTERFACE inet static
    address $address
    netmask $netmask
    gateway $gateway
    dns-nameservers $dns1 $dns2
EOF

    apply_network_config
}

# Função para configurar DHCP
configure_dhcp() {
    echo -e "\n${YELLOW}Configurando rede com DHCP...${NC}"
    create_backup
    
    cat > $CONFIG_FILE <<EOF
# Configuração gerada automaticamente
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto $INTERFACE
iface $INTERFACE inet dhcp
EOF

    apply_network_config
}

# Função para criar backup
create_backup() {
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${YELLOW}Criando backup da configuração atual...${NC}"
        cp "$CONFIG_FILE" "$BACKUP_FILE" 2>/dev/null || echo -e "${RED}AVISO: Não foi possível criar backup${NC}"
    fi
}

# Função para aplicar configuração de rede
apply_network_config() {
    echo -e "${YELLOW}Reiniciando interface de rede...${NC}"
    
    # Força parada completa da interface
    ifdown --force $INTERFACE >/dev/null 2>&1
    ip addr flush dev $INTERFACE 2>/dev/null
    systemctl stop networking.service >/dev/null 2>&1
    
    # Aplica nova configuração
    if ifup $INTERFACE; then
        echo -e "${YELLOW}Aguardando estabilização da rede (5 segundos)...${NC}"
        sleep 5  # Espera adicional para DHCP/roteamento
        
        if test_connection; then
            show_network_status
            return 0
        else
            echo -e "${RED}Aplicando fallback de configuração...${NC}"
            systemctl restart networking.service
            sleep 3
            if test_connection; then
                show_network_status
                return 0
            else
                return 1
            fi
        fi
    else
        echo -e "${RED}ERRO: Falha ao ativar interface!${NC}"
        return 1
    fi
}

# Função para restaurar backup
restore_backup() {
    if [ -f "$BACKUP_FILE" ]; then
        echo -e "\n${YELLOW}Restaurando configuração anterior...${NC}"
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        apply_network_config
    else
        echo -e "${RED}AVISO: Nenhum backup encontrado para restaurar.${NC}"
        return 1
    fi
}

# Função para mostrar status da rede
show_network_status() {
    echo -e "\n${GREEN}=== Status da Interface $INTERFACE ===${NC}"
    ip -br addr show $INTERFACE
    ip -br link show $INTERFACE
    
    echo -e "\n${GREEN}=== Rota Padrão ===${NC}"
    ip route | grep default || echo "Nenhuma rota padrão configurada"
    
    echo -e "\n${GREEN}=== Configuração de DNS ===${NC}"
    grep -v '^#' /etc/resolv.conf | grep -v '^$'
    
    echo -e "\n${GREEN}=== Teste de Conexão Extendido ===${NC}"
    test_connection
}

# Menu principal
while true; do
    clear
    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}  CONFIGURADOR DE REDE - DEBIAN  ${NC}"
    echo -e "${GREEN}====================================${NC}"
    echo
    echo -e "1) Configurar IP Estático - Casa (10.0.0.10/8)"
    echo -e "2) Configurar IP Estático - IFCE (10.211.209.150/21)"
    echo -e "3) Configurar DHCP (Obter IP automaticamente)"
    echo -e "4) Restaurar configuração anterior"
    echo -e "5) Mostrar status completo da rede"
    echo -e "6) Configurar tempo de teste (atual: ${TEST_TIMEOUT}s)"
    echo -e "7) Sair"
    echo
    read -p "Selecione uma opção [1-7]: " opt

    case $opt in
        1) configure_static "Casa" "10.0.0.10" "255.0.0.0" "10.0.0.1" "10.0.0.1" "8.8.8.8" ;;
        2) configure_static "IFCE" "10.211.209.150" "255.255.248.0" "10.211.208.1" "10.211.208.1" "8.8.8.8" ;;
        3) configure_dhcp ;;
        4) restore_backup ;;
        5) show_network_status ;;
        6) 
            read -p "Digite o novo tempo de teste em segundos: " new_timeout
            if [[ $new_timeout =~ ^[0-9]+$ ]] && [ $new_timeout -gt 0 ]; then
                TEST_TIMEOUT=$new_timeout
                echo -e "${GREEN}Tempo de teste alterado para ${TEST_TIMEOUT} segundos${NC}"
            else
                echo -e "${RED}Valor inválido! Usando o padrão (${TEST_TIMEOUT}s)${NC}"
            fi
            sleep 2
            ;;
        7) 
            echo -e "${GREEN}Saindo...${NC}"
            exit 0
            ;;
        *) 
            echo -e "${RED}Opção inválida!${NC}"
            sleep 1
            ;;
    esac
    
    read -p "Pressione Enter para continuar..."
done
