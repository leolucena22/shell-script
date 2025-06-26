# Guia de Instalação e Uso - DHCP Manager

## Descrição

Este sistema de gerenciamento DHCP foi desenvolvido para automatizar a configuração e administração do servidor DHCP no GNU/Linux Debian. O script oferece funcionalidades completas para gerenciar reservas de IP, controlar o serviço DHCP e automatizar backups.

## Características Principais

- **Menu Interativo**: Interface amigável para administração
- **Gerenciamento de Reservas**: Adicionar, listar e gerenciar reservas de IP
- **Controle de Serviço**: Start, stop e restart do servidor DHCP
- **Backup Automático**: Backup diário via CRON
- **Inicialização Automática**: Configuração automática no boot do sistema
- **Validação de Dados**: Validação de endereços MAC e IP
- **Logging**: Registro completo de todas as operações

## Pré-requisitos

1. Sistema GNU/Linux Debian (ou derivados)
2. Servidor DHCP ISC instalado:
   ```bash
   sudo apt update
   sudo apt install isc-dhcp-server
   ```
3. Privilégios de root para execução

## Instalação

### 1. Salvar o Script

```bash
# Criar diretório e salvar o script
sudo mkdir -p /opt/dhcp
sudo nano /opt/dhcp/dhcp_manager.sh

# Copiar o conteúdo do script para o arquivo
# Dar permissões de execução
sudo chmod +x /opt/dhcp/dhcp_manager.sh

# Criar link simbólico para facilitar o uso
sudo ln -s /opt/dhcp/dhcp_manager.sh /usr/local/bin/dhcp-manager
```

### 2. Primeira Execução

```bash
# Executar o script como root
sudo dhcp-manager
```

### 3. Configurações Iniciais

Na primeira execução, o script irá:
- Criar o diretório `/opt/dhcp/`
- Criar o arquivo de reservas `RESERVA.txt` com exemplos
- Configurar os diretórios de log

## Estrutura de Arquivos

```
/opt/dhcp/
├── dhcp_manager.sh          # Script principal
├── RESERVA.txt              # Arquivo de reservas (CSV)
├── backup_dhcp.sh           # Script de backup automático
└── backups/                 # Diretório de backups

/etc/dhcp/
├── dhcpd.conf              # Configuração principal do DHCP
└── dhcpd.conf.backup.*     # Backups manuais

/var/log/
└── dhcp_manager.log        # Log do sistema
```

## Formato do Arquivo de Reservas

O arquivo `RESERVA.txt` deve seguir o formato CSV:
```
Nome,MAC,IP
Diretoria,00:05:84:AB:EE:FF,192.168.0.1
Secretaria,00:05:84:EE:2B:45,192.168.0.2
Tesouraria,00:05:84:4E:CB:47,192.168.0.3
```

### Regras:
- Separador: vírgula (,)
- Nome: sem espaços ou caracteres especiais
- MAC: formato XX:XX:XX:XX:XX:XX
- IP: formato padrão IPv4

## Funcionalidades do Menu

### 1. Atualizar Faixa de IP do DHCP
- Permite alterar a faixa de IPs distribuídos automaticamente
- Padrão: 192.168.0.100 - 192.168.0.149

### 2. Acrescentar Máquina com Reserva de IP
- Adiciona nova reserva de IP para um MAC específico
- Atualiza automaticamente o arquivo `RESERVA.txt`
- Opção de aplicar imediatamente no servidor

### 3. Listar Reservas Existentes
- Exibe todas as reservas configuradas
- Formato tabular organizado

### 4. START - Iniciar Servidor DHCP
- Gera configuração baseada no arquivo de reservas
- Testa a configuração antes de iniciar
- Inicia o serviço DHCP

### 5. STOP - Parar Servidor DHCP
- Para o serviço DHCP de forma segura

### 6. RESTART - Reiniciar Servidor DHCP
- Combina STOP + START
- Útil após alterações na configuração

### 7. Configurar Backup Automático (CRON)
- Configura backup diário às 02:00
- Mantém últimos 30 backups
- Remove backups antigos automaticamente

### 8. Configurar Inicialização Automática
- Configura serviço systemd para boot
- Atualiza configuração automaticamente na inicialização

## Uso via Linha de Comando

```bash
# Executar o menu interativo
sudo dhcp-manager

# Inicialização automática (usado pelo systemd)
sudo dhcp-manager --boot-init
```

## Configuração do CRON

O backup automático é configurado para executar diariamente:
```bash
# Visualizar configuração do cron
sudo crontab -l

# Comando configurado:
# 0 2 * * * /opt/dhcp/backup_dhcp.sh
```

## Configuração de Inicialização Automática

O serviço systemd `dhcp-autostart.service` é criado para:
- Executar na inicialização do sistema
- Atualizar configurações automaticamente
- Iniciar o servidor DHCP

```bash
# Verificar status do serviço
sudo systemctl status dhcp-autostart.service

# Habilitar/desabilitar
sudo systemctl enable dhcp-autostart.service
sudo systemctl disable dhcp-autostart.service
```

## Logs e Monitoramento

### Visualizar Logs
```bash
# Log do sistema
sudo tail -f /var/log/dhcp_manager.log

# Log do servidor DHCP
sudo tail -f /var/log/syslog | grep dhcp
```

### Status do Servidor
```bash
# Verificar status do serviço
sudo systemctl status isc-dhcp-server

# Verificar configuração
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
```

## Troubleshooting

### Problemas Comuns

1. **Servidor não inicia**
   - Verificar sintaxe do arquivo de configuração
   - Verificar permissões dos arquivos
   - Verificar se a interface de rede está configurada

2. **Reservas não funcionam**
   - Verificar formato do arquivo RESERVA.txt
   - Verificar se MAC está correto
   - Reiniciar o servidor DHCP após alterações

3. **Backup não funciona**
   - Verificar permissões do script de backup
   - Verificar configuração do cron
   - Verificar espaço em disco

### Comandos de Diagnóstico

```bash
# Testar configuração DHCP
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf

# Verificar interfaces de rede
ip addr show

# Verificar processo DHCP
ps aux | grep dhcp

# Verificar portas de rede
sudo netstat -ulnp | grep :67
```

## Segurança

- Script deve ser executado apenas como root
- Arquivo de reservas deve ter permissões restritas
- Backups são armazenados com proteção de root
- Logs registram todas as operações

## Manutenção

### Tarefas Regulares
- Verificar logs semanalmente
- Limpar backups antigos mensalmente
- Atualizar arquivo de reservas conforme necessário
- Monitorar uso de IP na rede

### Atualizações
- Manter backup antes de qualquer alteração
- Testar configurações em ambiente de teste
- Documentar alterações realizadas

## Suporte

Para problemas ou dúvidas:
1. Consultar os logs do sistema
2. Verificar configuração dos arquivos
3. Consultar documentação do ISC DHCP Server
4. Verificar permissões e privilégios

## Considerações de Produção

- **Backup**: Sempre fazer backup antes de alterações
- **Teste**: Testar configurações em ambiente de desenvolvimento
- **Monitoramento**: Implementar monitoramento do serviço
- **Documentação**: Manter documentação das configurações
- **Segurança**: Restringir acesso aos arquivos de configuração
