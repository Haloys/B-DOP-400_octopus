#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_header() {
    clear
    echo -e "${BLUE}"
    echo "   ___   ___ _____ ___  ____  _   _ ____  "
    echo "  / _ \ / __|_   _/ _ \|  _ \| | | / ___| "
    echo " | | | | |    | || | | | |_) | | | \___ \ "
    echo " | |_| | |___ | || |_| |  __/| |_| |___) |"
    echo "  \___/ \____||_| \___/|_|    \___/|____/ "
    echo -e "${NC}"
    echo -e "${YELLOW}Ansible Deployment Manager${NC}"
    echo ""
}

show_help() {
    echo -e "${GREEN}Usage:${NC} $0 [command]"
    echo ""
    echo "Commands:"
    echo -e "  ${BLUE}setup${NC}         - Create vault password and prepare environment"
    echo -e "  ${BLUE}encrypt${NC}       - Encrypt a string (prompts for input)"
    echo -e "  ${BLUE}test${NC}          - Run playbook against test inventory"
    echo -e "  ${BLUE}deploy${NC}        - Run playbook against production inventory"
    echo -e "  ${BLUE}check-idempotence${NC} - Run playbook twice to test idempotence"
    echo -e "  ${BLUE}prepare${NC}       - Extract ZIP and create tarballs"
    echo -e "  ${BLUE}update-inventory${NC} - Update inventory with Azure VM IPs"
    echo ""
}

setup_env() {
    show_header
    echo -e "${YELLOW}Setting up environment...${NC}"
    echo -n "Enter a secure vault password (default: verySecretPassword): "
    read -s VAULT_PASS
    echo
    
    if [ -z "$VAULT_PASS" ]; then
        VAULT_PASS="verySecretPassword"
    fi
    
    echo "$VAULT_PASS" > /tmp/.vault_pass
    chmod 600 /tmp/.vault_pass
    echo -e "${GREEN}Vault password file created at /tmp/.vault_pass${NC}"
    
    export ANSIBLE_VAULT_PASSWORD_FILE=/tmp/.vault_pass
    
    CURRENT_SHELL=$(basename "$SHELL")
    
    case "$CURRENT_SHELL" in
        bash)
            RC_FILE=~/.bashrc
            ;;
        zsh)
            RC_FILE=~/.zshrc
            ;;
        *)
            echo -e "${YELLOW}Could not determine your shell's RC file. Using ~/.profile instead.${NC}"
            RC_FILE=~/.profile
            ;;
    esac
    
    if ! grep -q "ANSIBLE_VAULT_PASSWORD_FILE=/tmp/.vault_pass" "$RC_FILE"; then
        echo "export ANSIBLE_VAULT_PASSWORD_FILE=/tmp/.vault_pass" >> "$RC_FILE"
        echo -e "${GREEN}Environment variable added to $RC_FILE${NC}"
    fi
    
    echo -e "${GREEN}Environment configured!${NC}"
    echo -e "${YELLOW}You can now run:${NC} source $RC_FILE"
}

encrypt_string() {
    show_header
    echo -e "${YELLOW}Encrypt a string for use in Ansible variables${NC}"
    if [ ! -f /tmp/.vault_pass ]; then
        echo -e "${RED}Vault password file not found. Run 'setup' first.${NC}"
        exit 1
    fi
    echo -n "Enter the string to encrypt: "
    read -s SECRET_STRING
    echo
    echo -n "Enter the variable name: "
    read VAR_NAME
    ENCRYPTED=$(ANSIBLE_VAULT_PASSWORD_FILE=/tmp/.vault_pass ansible-vault encrypt_string "$SECRET_STRING" --name "$VAR_NAME" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Encrypted string:${NC}"
        echo "$ENCRYPTED"
        echo -e "${YELLOW}Copy this into your all.yml or other variable files${NC}"
    else
        echo -e "${RED}Encryption failed. Check that ansible-vault is installed and your vault password is correct.${NC}"
    fi
}

test_playbook() {
    show_header
    echo -e "${YELLOW}Running playbook against test inventory...${NC}"
    if [ ! -f production ]; then
        echo -e "${RED}Test inventory not found. Create production first.${NC}"
        exit 1
    fi
    
    if [ ! -f /tmp/.vault_pass ]; then
        echo -e "${YELLOW}Vault password file not found, creating it with default password...${NC}"
        echo "verySecretPassword" > /tmp/.vault_pass
        chmod 600 /tmp/.vault_pass
    fi
    
    export ANSIBLE_VAULT_PASSWORD_FILE=/tmp/.vault_pass
    
    ansible-playbook -i production playbook.yml --vault-password-file=/tmp/.vault_pass
    echo -e "${GREEN}Test run completed!${NC}"
}

deploy_playbook() {
    show_header
    echo -e "${YELLOW}Deploying to production...${NC}"
    echo -e "${RED}WARNING: This will run the playbook against production servers.${NC}"
    echo -n "Are you sure you want to continue? (y/N): "
    read CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo -e "${YELLOW}Deployment cancelled.${NC}"
        exit 0
    fi
    if [ ! -f production ]; then
        echo -e "${RED}Production inventory not found. The file should be named 'production'.${NC}"
        exit 1
    fi
    
    if [ ! -f /tmp/.vault_pass ]; then
        echo -e "${YELLOW}Vault password file not found, creating it with default password...${NC}"
        echo "verySecretPassword" > /tmp/.vault_pass
        chmod 600 /tmp/.vault_pass
    fi
    
    export ANSIBLE_VAULT_PASSWORD_FILE=/tmp/.vault_pass
    
    ansible-playbook -i production playbook.yml --vault-password-file=/tmp/.vault_pass
    echo -e "${GREEN}Deployment completed!${NC}"
}

check_idempotence() {
    show_header
    echo -e "${YELLOW}Testing idempotence...${NC}"
    if [ ! -f production ]; then
        echo -e "${RED}Test inventory not found. Create production first.${NC}"
        exit 1
    fi
    
    if [ ! -f /tmp/.vault_pass ]; then
        echo -e "${YELLOW}Vault password file not found, creating it with default password...${NC}"
        echo "verySecretPassword" > /tmp/.vault_pass
        chmod 600 /tmp/.vault_pass
    fi
    
    export ANSIBLE_VAULT_PASSWORD_FILE=/tmp/.vault_pass
    
    echo -e "${BLUE}First run:${NC}"
    ansible-playbook -i production playbook.yml --vault-password-file=/tmp/.vault_pass
    echo -e "${BLUE}Second run (should show minimal changes):${NC}"
    ansible-playbook -i production playbook.yml --vault-password-file=/tmp/.vault_pass
    echo -e "${GREEN}Idempotence test completed!${NC}"
    echo -e "${YELLOW}Look at the PLAY RECAP above. The 'changed' count should be 0 or very low in the second run.${NC}"
}

prepare_files() {
    show_header
    echo -e "${YELLOW}Preparing application files...${NC}"
    if ! command -v unzip &> /dev/null; then
        echo -e "${RED}unzip command not found. Installing...${NC}"
        sudo apt-get update && sudo apt-get install -y unzip
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to install unzip. Please install it manually.${NC}"
            exit 1
        fi
    fi
    if [ ! -f B-DOP_poll_application.zip ]; then
        echo -e "${RED}B-DOP_poll_application.zip not found${NC}"
        exit 1
    fi
    echo -e "${BLUE}Extracting application zip...${NC}"
    mkdir -p tmp_extract
    rm -rf tmp_extract/* 2>/dev/null
    unzip -q -o B-DOP_poll_application.zip -d tmp_extract
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to extract zip file. The file may be corrupted.${NC}"
        exit 1
    fi
    echo -e "${BLUE}Creating application tarballs...${NC}"
    echo -e "- Creating poll.tar..."
    if [ -d "tmp_extract/poll" ]; then
        tar -cf poll.tar -C tmp_extract/poll .
        echo -e "  ${GREEN}✓ poll.tar created${NC}"
    else
        echo -e "  ${RED}× poll directory not found${NC}"
        exit 1
    fi
    echo -e "- Creating result.tar..."
    if [ -d "tmp_extract/result" ]; then
        tar -cf result.tar -C tmp_extract/result .
        echo -e "  ${GREEN}✓ result.tar created${NC}"
    else
        echo -e "  ${RED}× result directory not found${NC}"
        exit 1
    fi
    echo -e "- Creating worker.tar..."
    if [ -d "tmp_extract/worker" ]; then
        tar -cf worker.tar -C tmp_extract/worker .
        echo -e "  ${GREEN}✓ worker.tar created${NC}"
    else
        echo -e "  ${RED}× worker directory not found${NC}"
        exit 1
    fi
    echo -e "${BLUE}Copying database schema...${NC}"
    mkdir -p roles/postgresql/files
    if [ -f "tmp_extract/schema.sql" ]; then
        cp tmp_extract/schema.sql roles/postgresql/files/
        echo -e "${GREEN}✓ schema.sql copied to roles/postgresql/files/${NC}"
    else
        echo -e "${RED}× schema.sql not found${NC}"
        exit 1
    fi
    rm -rf tmp_extract
    echo -e "${GREEN}All application files prepared successfully!${NC}"
}

update_inventory() {
    show_header
    echo -e "${YELLOW}Updating inventory file with Azure VM IPs...${NC}"
    echo "Do you have different SSH keys for different VM groups? (y/N): "
    read MULTIPLE_KEYS
    echo "Enter Azure username (default: ansible): "
    read AZURE_USER
    AZURE_USER=${AZURE_USER:-ansible}
    echo "Redis VM IP: "
    read REDIS_IP
    echo "PostgreSQL VM IP: "
    read POSTGRESQL_IP
    echo "Poll VM IP: "
    read POLL_IP
    echo "Worker VM IP: "
    read WORKER_IP
    echo "Result VM IP: "
    read RESULT_IP
    if [[ "$MULTIPLE_KEYS" == "y" || "$MULTIPLE_KEYS" == "Y" ]]; then
        echo -e "${BLUE}Setting up multiple SSH keys...${NC}"
        
        echo "Enter SSH key path for small VMs (Redis, Poll, Result): "
        read SMALL_KEY_PATH
        if [ ! -f "$SMALL_KEY_PATH" ]; then
            echo -e "${RED}SSH key file not found at $SMALL_KEY_PATH${NC}"
            exit 1
        fi
        
        echo "Enter SSH key path for large VMs (PostgreSQL, Worker): "
        read LARGE_KEY_PATH
        if [ ! -f "$LARGE_KEY_PATH" ]; then
            echo -e "${RED}SSH key file not found at $LARGE_KEY_PATH${NC}"
            exit 1
        fi
        cat > production << EOF
[redis]
redis-1 ansible_host=${REDIS_IP} ansible_ssh_private_key_file=${SMALL_KEY_PATH}

[postgresql]
postgresql-1 ansible_host=${POSTGRESQL_IP} ansible_ssh_private_key_file=${LARGE_KEY_PATH}

[poll]
poll-1 ansible_host=${POLL_IP} ansible_ssh_private_key_file=${SMALL_KEY_PATH}

[worker]
worker-1 ansible_host=${WORKER_IP} ansible_ssh_private_key_file=${LARGE_KEY_PATH}

[result]
result-1 ansible_host=${RESULT_IP} ansible_ssh_private_key_file=${SMALL_KEY_PATH}

[small:children]
redis
poll
result

[large:children]
postgresql
worker

[all:vars]
ansible_user=${AZURE_USER}
ansible_become=yes
ansible_become_method=sudo
EOF
    else
        echo "Enter path to SSH private key for all Azure VMs (e.g. ~/.ssh/octopus_key): "
        read SSH_KEY_PATH
        if [ ! -f "$SSH_KEY_PATH" ]; then
            echo -e "${RED}SSH key file not found at $SSH_KEY_PATH${NC}"
            exit 1
        fi
        cat > production << EOF
[redis]
redis-1 ansible_host=${REDIS_IP}

[postgresql]
postgresql-1 ansible_host=${POSTGRESQL_IP}

[poll]
poll-1 ansible_host=${POLL_IP}

[worker]
worker-1 ansible_host=${WORKER_IP}

[result]
result-1 ansible_host=${RESULT_IP}

[all:vars]
ansible_user=${AZURE_USER}
ansible_become=yes
ansible_become_method=sudo
ansible_ssh_private_key_file=${SSH_KEY_PATH}
EOF
    fi
    
    echo -e "${GREEN}✓ Inventory file 'production' created with Azure VM IPs${NC}"
    echo -e "${YELLOW}Testing SSH connectivity to all hosts...${NC}"
    
    export ANSIBLE_HOST_KEY_CHECKING=False
    ansible -i production all -m ping
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ All hosts are reachable${NC}"
    else
        echo -e "${RED}× Some hosts are not reachable. Please check your network connections and SSH keys.${NC}"
        echo -e "${YELLOW}Trying to ping individual groups...${NC}"
        
        if [[ "$MULTIPLE_KEYS" == "y" || "$MULTIPLE_KEYS" == "Y" ]]; then
            echo -e "${BLUE}Testing small VMs group (Redis, Poll, Result)...${NC}"
            ansible -i production small -m ping
            
            echo -e "${BLUE}Testing large VMs group (PostgreSQL, Worker)...${NC}"
            ansible -i production large -m ping
        else
            for group in redis postgresql poll worker result; do
                echo -e "${BLUE}Testing $group group...${NC}"
                ansible -i production $group -m ping
            done
        fi
    fi
}

if [ $# -eq 0 ]; then
    show_header
    show_help
    exit 0
fi

case "$1" in
    setup)
        setup_env
        ;;
    encrypt)
        encrypt_string
        ;;
    test)
        test_playbook
        ;;
    deploy)
        deploy_playbook
        ;;
    check-idempotence)
        check_idempotence
        ;;
    prepare)
        prepare_files
        ;;
    update-inventory)
        update_inventory
        ;;
    help)
        show_header
        show_help
        ;;
    *)
        show_header
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac

exit 0