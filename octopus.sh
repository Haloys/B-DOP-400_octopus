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
    echo -e "  ${BLUE}vm-setup${NC}      - Create and start Vagrant VMs for testing"
    echo -e "  ${BLUE}vm-stop${NC}       - Stop Vagrant VMs"
    echo -e "  ${BLUE}vm-destroy${NC}    - Remove Vagrant VMs"
    echo ""
}

setup_env() {
    show_header
    echo -e "${YELLOW}Setting up environment...${NC}"
    if [ ! -f ~/.vault_pass ]; then
        echo -n "Enter a secure vault password: "
        read -s VAULT_PASS
        echo
        echo "$VAULT_PASS" > ~/.vault_pass
        chmod 600 ~/.vault_pass
        echo -e "${GREEN}Vault password file created at ~/.vault_pass${NC}"
    else
        echo -e "${YELLOW}Vault password file already exists at ~/.vault_pass${NC}"
    fi
    export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass
    echo "export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass" >> ~/.bashrc
    echo -e "${GREEN}Environment configured!${NC}"
}

encrypt_string() {
    show_header
    echo -e "${YELLOW}Encrypt a string for use in Ansible variables${NC}"
    if [ ! -f ~/.vault_pass ]; then
        echo -e "${RED}Vault password file not found. Run 'setup' first.${NC}"
        exit 1
    fi
    echo -n "Enter the string to encrypt: "
    read -s SECRET_STRING
    echo
    echo -n "Enter the variable name: "
    read VAR_NAME
    ENCRYPTED=$(ansible-vault encrypt_string "$SECRET_STRING" --name "$VAR_NAME" 2>/dev/null)
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
    if [ ! -f inventory_localhost ]; then
        echo -e "${RED}Test inventory not found. Create inventory_localhost first.${NC}"
        exit 1
    fi
    ansible-playbook -i inventory_localhost playbook.yml -K
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
    ansible-playbook -i production playbook.yml
    echo -e "${GREEN}Deployment completed!${NC}"
}

check_idempotence() {
    show_header
    echo -e "${YELLOW}Testing idempotence...${NC}"
    if [ ! -f inventory_localhost ]; then
        echo -e "${RED}Test inventory not found. Create inventory_localhost first.${NC}"
        exit 1
    fi
    echo -e "${BLUE}First run:${NC}"
    ansible-playbook -i inventory_localhost playbook.yml
    echo -e "${BLUE}Second run (should show minimal changes):${NC}"
    ansible-playbook -i inventory_localhost playbook.yml
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

get_ssh_key() {
    echo "$1" | grep "$2 " | cut -d" " -f 4
}

vm_setup() {
    show_header
    echo -e "${YELLOW}Setting up and starting Vagrant VMs for Octopus testing...${NC}"
    if ! command -v vagrant &> /dev/null; then
        echo -e "${RED}Vagrant not found. Please install Vagrant first.${NC}"
        echo -e "${BLUE}Visit https://www.vagrantup.com/downloads for installation instructions.${NC}"
        exit 1
    fi
    mkdir -p production
    echo -e "${BLUE}Creating Vagrantfile...${NC}"
    cat > Vagrantfile << 'EOF'
IMAGE = "debian/bookworm64"
VM_COUNT = 5
Vagrant.configure("2") do |config|
  (1..VM_COUNT).each do |i|
    config.vm.define "VM#{i}" do |subconfig|
      subconfig.vm.box = IMAGE
      subconfig.vm.hostname = "VM#{i}"
      subconfig.vm.network "private_network", ip: "192.168.56.#{i+9}"
      subconfig.vm.provider "virtualbox" do |vb|
        # More memory for PostgreSQL and Worker
        if i == 2 || i == 4
          vb.memory = "1024"
        else
          vb.memory = "512"
        end
        vb.cpus = 1
      end
    end
  end
  config.vm.define "VM1" do |result|
    result.vm.network "forwarded_port", guest: 80, host: 5001
  end
  config.vm.define "VM3" do |poll|
    poll.vm.network "forwarded_port", guest: 80, host: 5000
  end
end
EOF
    echo -e "${GREEN}✓ Vagrantfile created${NC}"
    echo -e "${BLUE}Starting VMs (this may take several minutes)...${NC}"
    vagrant up
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error starting VMs. Please check Vagrant output for details.${NC}"
        exit 1
    fi
    echo -e "${BLUE}Generating Ansible inventory from VM configurations...${NC}"
    services=("result" "postgresql" "poll" "redis" "worker")
    sshVar=("HostName:host" "Port:port" "User:user" "IdentityFile:ssh_private_key_file")
    host="production"
    echo "[redis]" > $host
    echo "[postgresql]" >> $host
    echo "[poll]" >> $host
    echo "[worker]" >> $host
    echo "[result]" >> $host
    echo "" >> $host
    echo "[all:vars]" >> $host
    echo "ansible_become=yes" >> $host
    echo "ansible_become_method=sudo" >> $host
    for vm in $(seq 1 5)
    do
        service=${services[$vm - 1]}
        sshconfig=$(vagrant ssh-config VM$vm 2>/dev/null)
        if [ -z "$sshconfig" ]; then
            echo -e "${RED}ERROR: Could not get SSH config for VM$vm${NC}"
            exit 1
        fi
        hostname="${service}-1"
        host_line="$hostname "
        for var in "${sshVar[@]}"
        do
            res=$(get_ssh_key "$sshconfig" ${var%%:*})
            host_line+="ansible_${var#*:}=$res "
        done
        sed -i "/\[$service\]/a $host_line" $host
    done
    echo -e "${GREEN}✓ Inventory file generated at $host${NC}"
    echo -e "${GREEN}VMs started and inventory configured!${NC}"
    echo -e "${YELLOW}To run your playbook on these VMs, use:${NC}"
    echo -e "${BLUE}ansible-playbook -i production playbook.yml${NC}"
}

vm_stop() {
    show_header
    echo -e "${YELLOW}Stopping Vagrant VMs...${NC}"
    if [ ! -f Vagrantfile ]; then
        echo -e "${RED}Vagrantfile not found. Run 'vm-setup' first.${NC}"
        exit 1
    fi
    vagrant halt
    echo -e "${GREEN}VMs stopped!${NC}"
}

vm_destroy() {
    show_header
    echo -e "${YELLOW}Destroying Vagrant VMs...${NC}"
    if [ ! -f Vagrantfile ]; then
        echo -e "${RED}Vagrantfile not found. Nothing to destroy.${NC}"
        exit 1
    fi
    echo -e "${RED}WARNING: This will destroy all VMs and their data.${NC}"
    echo -n "Are you sure you want to continue? (y/N): "
    read CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo -e "${YELLOW}Destruction cancelled.${NC}"
        exit 0
    fi
    vagrant destroy -f
    echo -e "${GREEN}VMs destroyed!${NC}"
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
    vm-setup)
        vm_setup
        ;;
    vm-stop)
        vm_stop
        ;;
    vm-destroy)
        vm_destroy
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