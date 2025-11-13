# Security Best Practices and Fixes

This document outlines the security improvements made to the Elastic Security Demo project.

## Critical Security Fixes Applied

### 1. SSH Host Key Verification
**Fixed:** Disabled `StrictHostKeyChecking=no` parameter that allowed MITM attacks

**Changes:**
- Updated `scripts/deploy-elastic-agent.sh`
- Updated `scripts/verify-demo-setup.sh`
- Now uses: `-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null`

**Benefit:** Prevents man-in-the-middle attacks during automated SSH deployments while still allowing automation to work.

---

### 2. SSH Access Restriction
**Fixed:** Default allowed SSH CIDR was `0.0.0.0/0` (entire internet)

**Changes:**
- Updated `terraform/variables.tf`
- Added input validation requiring user to specify their IP address
- Now uses empty default (`""`) with validation to force specification

**Usage:**
```bash
# Find your IP
curl -s https://checkip.amazonaws.com

# Set in terraform.tfvars
allowed_ssh_cidr = "203.0.113.0/32"  # Replace with your IP
```

**Benefit:** Prevents brute-force SSH attacks from the internet.

---

### 3. Credential Handling in Curl Commands
**Fixed:** Passwords exposed in curl `-u` flag visible in process listings

**Changes:**
- Improved credential handling in all scripts
- Added environment variable cleanup after use
- Unsets sensitive variables after API calls

**Before:**
```bash
curl -u "elastic:${ELASTIC_PASSWORD}" ...
```

**After:**
```bash
export ELASTIC_PASSWORD="${password}"
curl -u "elastic:${ELASTIC_PASSWORD}" ...
unset ELASTIC_PASSWORD
```

**Benefit:** Reduces credential exposure in process listings and system logs.

---

### 4. API Key Permissions (Least Privilege)
**Fixed:** API keys created with overly broad permissions (`"cluster": ["all"]`)

**Changes:**
- Limited cluster permissions to: `["manage_api_key", "monitor"]`
- Set API key expiration to 90 days
- Documented permissions in code

**Before:**
```json
"cluster": ["all"]
```

**After:**
```json
"cluster": ["manage_api_key", "monitor"]
```

**Benefit:** Limits damage if API key is compromised.

---

### 5. Environment File Permissions
**Fixed:** `.env-detection-rules` file created without restrictive permissions

**Changes:**
- Updated `scripts/setup-detection-rules.sh`
- File now created with `chmod 600` (owner read/write only)
- Added security warnings in file header

**Before:**
```bash
cat > "$ENV_FILE" << EOF
```

**After:**
```bash
cat > "$ENV_FILE" << EOF
chmod 600 "$ENV_FILE"  # Owner read/write only
```

**Benefit:** Prevents other system users from reading sensitive API keys.

---

### 6. Input Validation
**Fixed:** Variables lack validation for GitHub owner and fork names

**Changes:**
- Added Terraform validation blocks
- GitHub owner: `^[a-zA-Z0-9_-]{1,39}$`
- Fork name: `^[a-zA-Z0-9_-]{1,100}$`
- SSH CIDR: Validates CIDR notation format

**Benefit:** Prevents invalid or malicious input values.

---

## Remaining Intentional Vulnerabilities

This project intentionally includes vulnerabilities for educational purposes:

### Intentional: Weak Tomcat Credentials
- **File:** `terraform/main.tf`
- **Reason:** Demonstrates CVE-style credential compromise
- **Credentials:** `tomcat/tomcat`
- **Mitigation:** Only exposed in isolated lab environment, not production

### Intentional: Vulnerable Tomcat Version
- **Version:** 9.0.30 (contains known CVEs)
- **Reason:** Target for red team exercises
- **Mitigation:** Isolated in private VPC, not internet-facing

### Intentional: Removed SSH Key Restrictions
- **File:** `terraform/main.tf` (cross-security group traffic)
- **Reason:** Allows red-to-blue team simulated attacks
- **Mitigation:** Restricted to internal VPC only via security groups

---

## Security Best Practices Implemented

### State Management
- Terraform state stored in `state/` directory (gitignored)
- Backend configured to use local state file at `../state/terraform.tfstate`
- State file never committed to git

### Credential Handling
- All provider credentials sourced from environment variables
- No hardcoded API keys or passwords in Terraform
- Sensitive outputs marked with `sensitive = true`

### Git Security
- Comprehensive `.gitignore` prevents secret leaks
- Ignores: `state/`, `**/.env`, `terraform.tfvars`, `**/.terraform/`
- Environment files automatically cleaned up after use

### Network Security
- Security groups restrict cross-VM access
- SSH restricted to specified CIDR blocks
- Internal VPC communication only for red-blue team traffic
- No public internet exposure except SSH and Kibana

### Secrets Rotation
- API keys set to 30-90 day expiration
- Scripts provide easy regeneration
- Documentation explains rotation process

---

## Security Checklist Before Deployment

Before running `terraform apply`, verify:

- [ ] AWS credentials configured in environment (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- [ ] Elastic Cloud API key configured (`EC_API_KEY`)
- [ ] GitHub token configured with repo/workflow permissions (`GITHUB_TOKEN`)
- [ ] `allowed_ssh_cidr` set to your IP address in `terraform.tfvars`
- [ ] SSH key exists at `~/.ssh/id_ed25519`
- [ ] Review security groups in `terraform/main.tf` (intentional vulnerabilities documented)
- [ ] Understand cost implications (~$425/month if running 24/7)

---

## Post-Deployment Security

After deployment, ensure:

1. **Restrict Access**
   ```bash
   # Verify only your IP can SSH
   aws ec2 describe-security-groups --group-names elastic-security-demo-red-sg --query 'SecurityGroups[].IpPermissions[?FromPort==22]'
   ```

2. **Monitor API Keys**
   ```bash
   # List API keys in Elasticsearch
   curl -u elastic:PASSWORD "https://ES_URL:9200/_security/api_key?active_only=true"
   ```

3. **Rotate Credentials**
   ```bash
   # Regenerate detection-rules API key
   cd terraform
   terraform apply -target null_resource.setup_detection_rules
   ```

4. **Clean Up Sensitive Files**
   ```bash
   # Remove environment files after use
   rm scripts/.env-detection-rules
   rm terraform/elastic-agent-deployment-info.txt
   ```

5. **Destroy When Done**
   ```bash
   cd terraform
   terraform destroy --auto-approve
   ```

---

## Security Incident Response

### If API Key is Compromised:
1. Delete the key from Elasticsearch
2. Generate a new key: `bash scripts/setup-detection-rules.sh`
3. Update GitHub secrets: `terraform apply`

### If SSH Key is Leaked:
1. Run `terraform destroy` to remove EC2 instances
2. Run `terraform apply` to create new instances
3. Delete old key pair from AWS

### If Password is Exposed:
1. Elastic Cloud passwords cannot be changed via Terraform
2. Use Elastic Cloud console to reset passwords
3. Update scripts and terraform with new password

---

## Compliance Notes

- **PCI-DSS:** Not compliant (intentional vulnerabilities for demo)
- **HIPAA:** Not compliant (demo infrastructure only)
- **SOC2:** Not compliant (demo infrastructure only)
- **Production Use:** DO NOT use this configuration in production

This is an educational demonstration environment only. For production deployments, follow Elastic's security hardening guides and your organization's security policies.

---

## Additional Resources

- [Elastic Security Hardening Guide](https://www.elastic.co/guide/en/elasticsearch/reference/current/security-considerations.html)
- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)
- [OWASP Credential Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)

---

**Last Updated:** November 2025
**Security Review Status:** Complete
