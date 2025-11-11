# Local Machine Setup - Python Virtual Environment and Detection Rules

## Overview

This guide provides step-by-step instructions for setting up your local machine with a Python virtual environment and the detection-rules CLI for rule development.

**Estimated Setup Time:** 10-15 minutes

---

## Prerequisites

- **Python 3.12+** installed (REQUIRED - detection-rules requires Python 3.12 or higher)
- Git installed
- GitHub CLI (`gh`) for authentication (optional but recommended)

### Install and Configure Python 3.12

```bash
# Install Python 3.12
brew install python@3.12

# Make Python 3.12 the default python3 command
brew unlink python@3.13  # If you have 3.13 installed
brew unlink python@3.12 && brew link --overwrite python@3.12
ln -sf /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3

# Ensure Homebrew binaries are prioritized in PATH
echo 'export PATH="/opt/homebrew/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Verify python3 now points to 3.12
python3 --version  # Should show Python 3.12.x

# Check git
git --version
```

**Important:** The detection-rules package requires Python 3.12+. Using Python 3.11 or earlier will result in an error.

---

## Step-by-Step Virtual Environment Setup

### 1. Clone the Detection Rules Fork

```bash
# Navigate to your home directory (or wherever you prefer)
cd ~

# Clone the detection-rules fork
git clone https://github.com/stuartMoorhouse/security-demo-detection-rules.git

# Navigate into the repository
cd security-demo-detection-rules
```

### 2. Create Virtual Environment

```bash
# Create a virtual environment (Python 3.12 should be your default now)
python3 -m venv .venv
```

This creates a `.venv` directory containing:
- Python 3.12 interpreter
- pip package manager
- Isolated package installation location

**Note:** If you see an error about Python version, verify `python3 --version` shows 3.12.x. If not, follow the Prerequisites section to configure Python 3.12 as your default.

### 3. Activate Virtual Environment

```bash
# Activate the virtual environment
source .venv/bin/activate
```

**You should now see `(.venv)` at the beginning of your terminal prompt**, indicating the virtual environment is active.

### 4. Upgrade pip

```bash
# Upgrade pip to the latest version
pip install --upgrade pip
```

### 5. Install Detection Rules Package

```bash
# Install detection-rules in editable mode with dev dependencies
pip install -e ".[dev]"
```

This will install:
- The detection-rules package
- All required dependencies
- Development tools for testing and validation

**Installation may take 2-3 minutes.**

### 6. Verify Installation

```bash
# Check detection-rules CLI is working
python -m detection_rules --help

---

## Quick Reference Commands

### Activate Virtual Environment

**Run this every time you open a new terminal session:**

```bash
cd ~/security-demo-detection-rules
source .venv/bin/activate
```

### Deactivate Virtual Environment

**Run this when you're done working:**

```bash
deactivate
```

### Check if Virtual Environment is Active

```bash
# Check Python location (should show .venv path)
which python

# Expected output:
# ~/security-demo-detection-rules/.venv/bin/python
```

---

## Complete Workflow Example

Here's a typical workflow for working with detection rules:

```bash
# 1. Start fresh terminal session
cd ~/security-demo-detection-rules

# 2. Activate virtual environment
source .venv/bin/activate

# 3. Verify you're in the right environment
which python  # Should show .venv path

# 4. Now you can use detection-rules commands
python -m detection_rules view-rule rules/linux/execution_web_shell_detection.toml

# 5. Run tests on a rule
python -m detection_rules test rules/linux/execution_web_shell_detection.toml

# 6. Export a rule from Kibana
## get the enviromental variables from Terraform output
../security-demo-2025/scripts/setup-detection-rules.sh
source ../security-demo-2025/scripts/.env-detection-rules


python -m detection_rules kibana --cloud-id="${LOCAL_CLOUD_ID}" --api-key="${LOCAL_API_KEY}" export-rules --rule-id "50052ec2-ae29-48b7-a897-4e349c9bb2d3" --directory custom-rules/rules/ --strip-version

# 7. When done, deactivate
deactivate
```

---

## Optional: Create Activation Helper Script

To make activation easier, create a helper script:

```bash
# Create the helper script
cat > ~/activate-detection-rules.sh << 'EOF'
#!/bin/bash
cd ~/security-demo-detection-rules && source .venv/bin/activate
EOF

# Make it executable
chmod +x ~/activate-detection-rules.sh
```

Now you can activate with a single command:

```bash
source ~/activate-detection-rules.sh
```

---

## Troubleshooting

### Issue: `ERROR: Package 'detection-rules' requires a different Python: 3.11.x not in '>=3.12'`

**Cause:** Your `python3` command points to Python 3.11 or earlier, but detection-rules requires Python 3.12+.

**Solution:** Configure Python 3.12 as your default:

```bash
# 1. Install Python 3.12 if not already installed
brew install python@3.12

# 2. Make Python 3.12 the default python3
brew unlink python@3.13  # If you have 3.13 installed
brew unlink python@3.12 && brew link --overwrite python@3.12
ln -sf /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3

# 3. Update your shell PATH (if not already done)
echo 'export PATH="/opt/homebrew/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 4. Verify python3 now shows 3.12
python3 --version  # Should show Python 3.12.x

# 5. Remove the old virtual environment if it exists
cd ~/security-demo-detection-rules
rm -rf .venv

# 6. Create new virtual environment with Python 3.12
python3 -m venv .venv

# 7. Activate and install
source .venv/bin/activate
pip install --upgrade pip
pip install -e ".[dev]"
```

### Issue: `python3 --version` still shows wrong version after configuration

**Solution:** Restart your terminal or reload shell configuration:
```bash
# Reload shell configuration
source ~/.zshrc

# Or open a new terminal window
# Then verify
python3 --version  # Should now show Python 3.12.x
```

### Issue: `pip install -e ".[dev]"` fails with dependency errors

**Solution:** Upgrade pip first:
```bash
pip install --upgrade pip setuptools wheel
pip install -e ".[dev]"
```

### Issue: Virtual environment not activating

**Solution:** Check the path and use full path:
```bash
source ~/security-demo-detection-rules/.venv/bin/activate
```

### Issue: `which python` shows system Python, not .venv

**Solution:** Make sure you activated the virtual environment:
```bash
# Deactivate first if needed
deactivate

# Then activate again
source .venv/bin/activate

# Verify
which python  # Should show .venv path
```

### Issue: Command not found after activation

**Solution:** Make sure you're in the repository directory:
```bash
cd ~/security-demo-detection-rules
source .venv/bin/activate
```

---

## What's Next?

After completing this setup, you can:

1. **Configure Elastic Cloud Connections** - See `local-setup.md` for connecting to your Elastic Cloud deployments
2. **Start Rule Development** - Create and test detection rules locally
3. **Use CI/CD Workflow** - Push rules to GitHub for automatic deployment

---

## Additional Resources

- [Detection Rules CLI Documentation](https://github.com/elastic/detection-rules)
- [Python Virtual Environments Guide](https://docs.python.org/3/tutorial/venv.html)
- [Elastic Detection Rules Repository](https://github.com/elastic/detection-rules)

---

## Summary Checklist

- [ ] Python 3.12+ installed and configured as default (`python3 --version` shows 3.12.x)
- [ ] Homebrew bin directory prioritized in PATH
- [ ] Cloned detection-rules fork
- [ ] Created `.venv` virtual environment using `python3 -m venv .venv`
- [ ] Activated virtual environment
- [ ] Upgraded pip
- [ ] Installed detection-rules package with `pip install -e ".[dev]"`
- [ ] Verified installation with `python -m detection_rules --help`
- [ ] Bookmarked activation command: `source .venv/bin/activate`

Once all items are checked, your local machine is ready for detection rule development!
