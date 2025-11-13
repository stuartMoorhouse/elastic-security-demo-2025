#!/bin/bash

################################################################################
# Elastic Security Demo - Infrastructure Verification Script
#
# Purpose: Verify that all infrastructure components are properly configured
#          and ready for the purple team exercise demo
#
# Usage: ./verify-demo-setup.sh
#
# Requirements:
#   - Run from project root directory
#   - Terraform state must exist in terraform/
#   - AWS CLI configured
#   - SSH access to EC2 instances
#
# Author: Stuart, Elastic Security Sales Engineering
# Last Updated: November 2025
################################################################################

set -o pipefail  # Exit on pipe failure
set -o nounset   # Exit on undefined variable
# Note: errexit is NOT set - we handle errors manually for each test

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Counters for test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0
TESTS_TOTAL=0

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo -e "${BOLD}${BLUE}$1${NC}"
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}## $1${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

print_failure() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((TESTS_WARNING++))
    ((TESTS_TOTAL++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_step() {
    echo -e "  → $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

run_ssh_command() {
    local host="$1"
    local command="$2"
    local timeout="${3:-10}"

    ssh -o ConnectTimeout="${timeout}" \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -i ~/.ssh/id_ed25519 \
        "ubuntu@${host}" \
        "${command}" 2>/dev/null
}

################################################################################
# Verification Functions
################################################################################

verify_local_prerequisites() {
    print_section "Local Machine Prerequisites"

    # Check Terraform
    if check_command terraform; then
        local tf_version=$(terraform version -json | jq -r '.terraform_version')
        print_success "Terraform installed (version ${tf_version})"
    else
        print_failure "Terraform not installed"
    fi

    # Check AWS CLI
    if check_command aws; then
        local aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
        print_success "AWS CLI installed (version ${aws_version})"
    else
        print_failure "AWS CLI not installed"
    fi

    # Check jq
    if check_command jq; then
        print_success "jq installed (JSON parser)"
    else
        print_warning "jq not installed (optional, but recommended)"
    fi

    # Check curl
    if check_command curl; then
        print_success "curl installed"
    else
        print_failure "curl not installed"
    fi

    # Check SSH key
    if [[ -f ~/.ssh/id_ed25519 ]]; then
        print_success "SSH key exists (~/.ssh/id_ed25519)"
    elif [[ -f ~/.ssh/id_rsa ]]; then
        print_warning "Using RSA key (~/.ssh/id_rsa) - ed25519 preferred"
    else
        print_failure "No SSH key found (~/.ssh/id_ed25519)"
    fi

    # Check Terraform directory
    if [[ -d "${TERRAFORM_DIR}" ]]; then
        print_success "Terraform directory exists"
    else
        print_failure "Terraform directory not found: ${TERRAFORM_DIR}"
        exit 1
    fi

    # Check Terraform state
    if [[ -f "${TERRAFORM_DIR}/state/terraform.tfstate" ]]; then
        print_success "Terraform state file exists"
    else
        print_failure "Terraform state not found (run 'terraform apply' first)"
        exit 1
    fi
}

get_terraform_output() {
    local output_name="$1"
    cd "${TERRAFORM_DIR}"
    terraform output -raw "${output_name}" 2>/dev/null || echo ""
}

get_terraform_output_json() {
    local output_name="$1"
    cd "${TERRAFORM_DIR}"
    terraform output -json "${output_name}" 2>/dev/null || echo "{}"
}

verify_terraform_outputs() {
    print_section "Terraform Outputs"

    # Get VM information
    RED_VM_JSON=$(get_terraform_output_json "red_vm")
    BLUE_VM_JSON=$(get_terraform_output_json "blue_vm")

    RED_VM_PUBLIC_IP=$(echo "${RED_VM_JSON}" | jq -r '.public_ip // empty')
    RED_VM_PRIVATE_IP=$(echo "${RED_VM_JSON}" | jq -r '.private_ip // empty')
    BLUE_VM_PUBLIC_IP=$(echo "${BLUE_VM_JSON}" | jq -r '.public_ip // empty')
    BLUE_VM_PRIVATE_IP=$(echo "${BLUE_VM_JSON}" | jq -r '.private_ip // empty')

    if [[ -n "${RED_VM_PUBLIC_IP}" ]] && [[ "${RED_VM_PUBLIC_IP}" != "null" ]]; then
        print_success "Red Team VM public IP: ${RED_VM_PUBLIC_IP}"
        export RED_VM_PUBLIC_IP
    else
        print_failure "Red Team VM public IP not found"
    fi

    if [[ -n "${RED_VM_PRIVATE_IP}" ]] && [[ "${RED_VM_PRIVATE_IP}" != "null" ]]; then
        print_success "Red Team VM private IP: ${RED_VM_PRIVATE_IP}"
        export RED_VM_PRIVATE_IP
    else
        print_failure "Red Team VM private IP not found"
    fi

    if [[ -n "${BLUE_VM_PUBLIC_IP}" ]] && [[ "${BLUE_VM_PUBLIC_IP}" != "null" ]]; then
        print_success "Blue Team VM public IP: ${BLUE_VM_PUBLIC_IP}"
        export BLUE_VM_PUBLIC_IP
    else
        print_failure "Blue Team VM public IP not found"
    fi

    if [[ -n "${BLUE_VM_PRIVATE_IP}" ]] && [[ "${BLUE_VM_PRIVATE_IP}" != "null" ]]; then
        print_success "Blue Team VM private IP: ${BLUE_VM_PRIVATE_IP}"
        export BLUE_VM_PRIVATE_IP
    else
        print_failure "Blue Team VM private IP not found"
    fi

    # Get Elastic Cloud information
    ELASTIC_LOCAL_JSON=$(get_terraform_output_json "elastic_local")
    ELASTIC_DEV_JSON=$(get_terraform_output_json "elastic_dev")

    KIBANA_LOCAL_URL=$(echo "${ELASTIC_LOCAL_JSON}" | jq -r '.kibana_url // empty')
    KIBANA_DEV_URL=$(echo "${ELASTIC_DEV_JSON}" | jq -r '.kibana_url // empty')

    if [[ -n "${KIBANA_LOCAL_URL}" ]] && [[ "${KIBANA_LOCAL_URL}" != "null" ]]; then
        print_success "Elastic Cloud (local) Kibana URL configured"
        export KIBANA_LOCAL_URL
    else
        print_failure "Elastic Cloud (local) Kibana URL not found"
    fi

    if [[ -n "${KIBANA_DEV_URL}" ]] && [[ "${KIBANA_DEV_URL}" != "null" ]]; then
        print_success "Elastic Cloud (dev) Kibana URL configured"
        export KIBANA_DEV_URL
    else
        print_failure "Elastic Cloud (dev) Kibana URL not found"
    fi

    # Get GitHub information
    GITHUB_REPO_JSON=$(get_terraform_output_json "github_repository")
    GITHUB_REPO_URL=$(echo "${GITHUB_REPO_JSON}" | jq -r '.html_url // empty')

    if [[ -n "${GITHUB_REPO_URL}" ]] && [[ "${GITHUB_REPO_URL}" != "null" ]]; then
        print_success "GitHub repository URL: ${GITHUB_REPO_URL}"
        export GITHUB_REPO_URL
    else
        print_failure "GitHub repository URL not found"
    fi
}

verify_ssh_connectivity() {
    print_section "SSH Connectivity"

    # Test SSH to red team VM
    print_step "Testing SSH to red team VM (${RED_VM_PUBLIC_IP})..."
    if run_ssh_command "${RED_VM_PUBLIC_IP}" "echo 'SSH test successful'" 30; then
        print_success "SSH connection to red team VM successful"
    else
        print_failure "Cannot SSH to red team VM"
        print_info "Try: ssh -i ~/.ssh/id_ed25519 ubuntu@${RED_VM_PUBLIC_IP}"
    fi

    # Test SSH to blue team VM
    print_step "Testing SSH to blue team VM (${BLUE_VM_PUBLIC_IP})..."
    if run_ssh_command "${BLUE_VM_PUBLIC_IP}" "echo 'SSH test successful'" 30; then
        print_success "SSH connection to blue team VM successful"
    else
        print_failure "Cannot SSH to blue team VM"
        print_info "Try: ssh -i ~/.ssh/id_ed25519 ubuntu@${BLUE_VM_PUBLIC_IP}"
    fi
}

verify_red_team_vm() {
    print_section "Red Team VM (red-01) Configuration"

    print_step "Waiting for red team VM to complete initialization..."
    sleep 5  # Give user_data script time to run

    # Check hostname
    local hostname=$(run_ssh_command "${RED_VM_PUBLIC_IP}" "hostname" 10)
    if [[ "${hostname}" == "red-01" ]]; then
        print_success "Hostname set correctly: ${hostname}"
    else
        print_warning "Hostname is '${hostname}', expected 'red-01'"
    fi

    # Check Metasploit installation
    print_step "Checking Metasploit installation..."
    if run_ssh_command "${RED_VM_PUBLIC_IP}" "command -v msfconsole" 10 > /dev/null; then
        local msf_version=$(run_ssh_command "${RED_VM_PUBLIC_IP}" "msfconsole --version 2>/dev/null | head -1" 10)
        print_success "Metasploit Framework installed: ${msf_version}"
    else
        print_failure "Metasploit Framework not installed"
        print_info "Installation may still be in progress (check logs)"
    fi

    # Check Metasploit database
    print_step "Checking Metasploit database status..."
    local msfdb_status=$(run_ssh_command "${RED_VM_PUBLIC_IP}" "msfdb status 2>/dev/null || echo 'not initialized'" 10)
    if echo "${msfdb_status}" | grep -q "Database started"; then
        print_success "Metasploit database initialized and running"
    elif echo "${msfdb_status}" | grep -q "not initialized"; then
        print_warning "Metasploit database not initialized (run 'msfdb init' on red-01)"
    else
        print_warning "Metasploit database status unclear: ${msfdb_status}"
    fi

    # Check additional tools
    print_step "Checking additional tools..."
    local tools_ok=true

    if run_ssh_command "${RED_VM_PUBLIC_IP}" "command -v nmap" 10 > /dev/null; then
        print_success "nmap installed"
    else
        print_failure "nmap not installed"
        tools_ok=false
    fi

    if run_ssh_command "${RED_VM_PUBLIC_IP}" "command -v nc" 10 > /dev/null; then
        print_success "netcat installed"
    else
        print_failure "netcat not installed"
        tools_ok=false
    fi

    # Check setup log
    print_step "Checking setup completion..."
    if run_ssh_command "${RED_VM_PUBLIC_IP}" "test -f /var/log/elastic-demo-setup.log" 10; then
        if run_ssh_command "${RED_VM_PUBLIC_IP}" "grep -q 'Setup Complete' /var/log/elastic-demo-setup.log 2>/dev/null" 10; then
            print_success "Red team VM setup completed successfully"
        else
            print_warning "Red team VM setup may still be in progress"
            print_info "Monitor: ssh ubuntu@${RED_VM_PUBLIC_IP} 'tail -f /var/log/elastic-demo-setup.log'"
        fi
    else
        print_warning "Setup log not found (setup may still be running)"
    fi
}

verify_blue_team_vm() {
    print_section "Blue Team VM (blue-01) Configuration"

    print_step "Waiting for blue team VM to complete initialization..."
    sleep 5

    # Check hostname
    local hostname=$(run_ssh_command "${BLUE_VM_PUBLIC_IP}" "hostname" 10)
    if [[ "${hostname}" == "blue-01" ]]; then
        print_success "Hostname set correctly: ${hostname}"
    else
        print_warning "Hostname is '${hostname}', expected 'blue-01'"
    fi

    # Check Java installation
    print_step "Checking Java installation..."
    if run_ssh_command "${BLUE_VM_PUBLIC_IP}" "command -v java" 10 > /dev/null; then
        local java_version=$(run_ssh_command "${BLUE_VM_PUBLIC_IP}" "java -version 2>&1 | head -1 | cut -d'\"' -f2" 10)
        print_success "Java installed: ${java_version}"
    else
        print_failure "Java not installed"
    fi

    # Check Tomcat service
    print_step "Checking Tomcat service..."
    if run_ssh_command "${BLUE_VM_PUBLIC_IP}" "systemctl is-active tomcat" 10 | grep -q "active"; then
        print_success "Tomcat service is running"
    else
        print_failure "Tomcat service is not running"
        print_info "Check logs: ssh ubuntu@${BLUE_VM_PUBLIC_IP} 'sudo journalctl -u tomcat -n 50'"
    fi

    # Check Tomcat port
    print_step "Checking if port 8080 is listening..."
    if run_ssh_command "${BLUE_VM_PUBLIC_IP}" "sudo netstat -tlnp 2>/dev/null | grep ':8080'" 10 > /dev/null; then
        print_success "Port 8080 is listening"
    else
        print_failure "Port 8080 is not listening"
    fi

    # Check Tomcat version
    print_step "Checking Tomcat version..."
    local tomcat_version=$(run_ssh_command "${BLUE_VM_PUBLIC_IP}" "cat /opt/tomcat/RELEASE-NOTES 2>/dev/null | grep -m1 'Apache Tomcat Version' | cut -d' ' -f4" 10)
    if [[ "${tomcat_version}" == "9.0.30" ]]; then
        print_success "Tomcat version 9.0.30 (vulnerable version for demo)"
    elif [[ -n "${tomcat_version}" ]]; then
        print_warning "Tomcat version ${tomcat_version} (expected 9.0.30)"
    else
        print_failure "Could not determine Tomcat version"
    fi

    # Check Tomcat HTTP response (from local machine)
    print_step "Testing Tomcat HTTP response..."
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://${BLUE_VM_PUBLIC_IP}:8080" --connect-timeout 10 2>/dev/null || echo "000")
    if [[ "${http_code}" == "200" ]]; then
        print_success "Tomcat responds on http://${BLUE_VM_PUBLIC_IP}:8080"
    else
        print_failure "Tomcat not responding (HTTP ${http_code})"
        print_info "Check security groups allow traffic from your IP"
    fi

    # Check Tomcat Manager with weak credentials
    print_step "Testing Tomcat Manager with weak credentials..."
    local manager_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -u tomcat:tomcat \
        "http://${BLUE_VM_PUBLIC_IP}:8080/manager/text/list" \
        --connect-timeout 10 2>/dev/null || echo "000")
    if [[ "${manager_code}" == "200" ]]; then
        print_success "Tomcat Manager accessible with weak credentials (tomcat/tomcat)"
    else
        print_failure "Tomcat Manager not accessible (HTTP ${manager_code})"
        print_info "This is required for the demo to work"
    fi

    # Check setup log
    print_step "Checking setup completion..."
    if run_ssh_command "${BLUE_VM_PUBLIC_IP}" "test -f /var/log/elastic-demo-setup.log" 10; then
        if run_ssh_command "${BLUE_VM_PUBLIC_IP}" "grep -q 'Setup Complete' /var/log/elastic-demo-setup.log 2>/dev/null" 10; then
            print_success "Blue team VM setup completed successfully"
        else
            print_warning "Blue team VM setup may still be in progress"
            print_info "Monitor: ssh ubuntu@${BLUE_VM_PUBLIC_IP} 'tail -f /var/log/elastic-demo-setup.log'"
        fi
    else
        print_warning "Setup log not found (setup may still be running)"
    fi
}

verify_network_connectivity() {
    print_section "Inter-VM Network Connectivity"

    # Test red -> blue on port 8080
    print_step "Testing red team → blue team on port 8080..."
    local test_result=$(run_ssh_command "${RED_VM_PUBLIC_IP}" \
        "curl -s -o /dev/null -w '%{http_code}' http://${BLUE_VM_PRIVATE_IP}:8080 --connect-timeout 5 2>/dev/null || echo '000'" 10)
    if [[ "${test_result}" == "200" ]]; then
        print_success "Red team can reach blue team Tomcat (HTTP 200)"
    else
        print_failure "Red team cannot reach blue team Tomcat (HTTP ${test_result})"
        print_info "Check security groups allow traffic between VMs"
    fi

    # Test ICMP (ping) connectivity
    print_step "Testing ICMP connectivity (red → blue)..."
    if run_ssh_command "${RED_VM_PUBLIC_IP}" "ping -c 1 -W 2 ${BLUE_VM_PRIVATE_IP}" 10 > /dev/null 2>&1; then
        print_success "ICMP connectivity working (red → blue)"
    else
        print_failure "ICMP connectivity not working (red → blue)"
    fi

    # Test Tomcat Manager from red team
    print_step "Testing Tomcat Manager access from red team..."
    local manager_test=$(run_ssh_command "${RED_VM_PUBLIC_IP}" \
        "curl -s -u tomcat:tomcat http://${BLUE_VM_PRIVATE_IP}:8080/manager/text/list 2>/dev/null | head -1" 10)
    if echo "${manager_test}" | grep -q "OK"; then
        print_success "Red team can access Tomcat Manager with weak credentials"
    else
        print_failure "Red team cannot access Tomcat Manager"
        print_info "This is critical for the demo exploit to work"
    fi
}

verify_elastic_cloud() {
    print_section "Elastic Cloud Deployments"

    # Test local Kibana
    print_step "Testing Elastic Cloud (local) Kibana..."
    local kibana_local_code=$(curl -s -o /dev/null -w "%{http_code}" \
        "${KIBANA_LOCAL_URL}" \
        --connect-timeout 10 \
        --max-time 20 2>/dev/null || echo "000")
    if [[ "${kibana_local_code}" == "200" ]] || [[ "${kibana_local_code}" == "302" ]]; then
        print_success "Kibana (local) is accessible: ${KIBANA_LOCAL_URL}"
    else
        print_failure "Kibana (local) not accessible (HTTP ${kibana_local_code})"
    fi

    # Test dev Kibana
    print_step "Testing Elastic Cloud (dev) Kibana..."
    local kibana_dev_code=$(curl -s -o /dev/null -w "%{http_code}" \
        "${KIBANA_DEV_URL}" \
        --connect-timeout 10 \
        --max-time 20 2>/dev/null || echo "000")
    if [[ "${kibana_dev_code}" == "200" ]] || [[ "${kibana_dev_code}" == "302" ]]; then
        print_success "Kibana (dev) is accessible: ${KIBANA_DEV_URL}"
    else
        print_failure "Kibana (dev) not accessible (HTTP ${kibana_dev_code})"
    fi

    print_info "Note: Authentication testing requires credentials from terraform outputs"
}

verify_github_setup() {
    print_section "GitHub Repository and CI/CD"

    # Test if repository is accessible
    print_step "Testing GitHub repository access..."
    local repo_code=$(curl -s -o /dev/null -w "%{http_code}" \
        "${GITHUB_REPO_URL}" \
        --connect-timeout 10 2>/dev/null || echo "000")
    if [[ "${repo_code}" == "200" ]]; then
        print_success "GitHub repository accessible: ${GITHUB_REPO_URL}"
    else
        print_failure "GitHub repository not accessible (HTTP ${repo_code})"
    fi

    # Check if dev branch exists
    print_step "Checking for dev branch..."
    local dev_branch_code=$(curl -s -o /dev/null -w "%{http_code}" \
        "${GITHUB_REPO_URL}/tree/dev" \
        --connect-timeout 10 2>/dev/null || echo "000")
    if [[ "${dev_branch_code}" == "200" ]]; then
        print_success "Dev branch exists in repository"
    else
        print_warning "Dev branch may not exist (HTTP ${dev_branch_code})"
    fi

    # Check if workflow exists
    print_step "Checking for CI/CD workflow..."
    local workflow_url="${GITHUB_REPO_URL}/blob/dev/.github/workflows/deploy-to-dev.yml"
    local workflow_code=$(curl -s -o /dev/null -w "%{http_code}" \
        "${workflow_url}" \
        --connect-timeout 10 2>/dev/null || echo "000")
    if [[ "${workflow_code}" == "200" ]]; then
        print_success "CI/CD workflow file exists"
    else
        print_warning "CI/CD workflow may not exist (HTTP ${workflow_code})"
    fi
}

print_summary() {
    print_header "Verification Summary"

    echo -e "Total Tests: ${TESTS_TOTAL}"
    echo -e "${GREEN}Passed:      ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed:      ${TESTS_FAILED}${NC}"
    echo -e "${YELLOW}Warnings:    ${TESTS_WARNING}${NC}"
    echo ""

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All critical checks passed!${NC}"
        echo ""
        echo "Your infrastructure is ready for the demo."
        echo ""
        echo "Next steps:"
        echo "  1. SSH to red team VM: ssh -i ~/.ssh/id_ed25519 ubuntu@${RED_VM_PUBLIC_IP}"
        echo "  2. SSH to blue team VM: ssh -i ~/.ssh/id_ed25519 ubuntu@${BLUE_VM_PUBLIC_IP}"
        echo "  3. Follow demo-script/demo-execution-script.md"
        echo ""
        return 0
    else
        echo -e "${RED}${BOLD}✗ Some checks failed${NC}"
        echo ""
        echo "Please review the failures above and fix any issues before running the demo."
        echo ""
        if [[ ${TESTS_FAILED} -gt 0 ]]; then
            echo "Common issues:"
            echo "  - VMs may still be initializing (wait 2-3 minutes and re-run)"
            echo "  - Security groups may need adjustment"
            echo "  - SSH keys may not be configured correctly"
            echo ""
        fi
        return 1
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header "Elastic Security Demo - Infrastructure Verification"

    echo "This script will verify that your infrastructure is ready for the demo."
    echo "Estimated time: 1-2 minutes"
    echo ""

    # Run all verification checks
    verify_local_prerequisites
    verify_terraform_outputs
    verify_ssh_connectivity
    verify_red_team_vm
    verify_blue_team_vm
    verify_network_connectivity
    verify_elastic_cloud
    verify_github_setup

    # Print summary and exit with appropriate code
    print_summary
}

# Execute main function
main "$@"
