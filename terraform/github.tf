# Create standalone detection-rules repository (not a fork)
resource "null_resource" "fork_detection_rules" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Creating standalone detection-rules repository..."

      # Check if repository already exists
      if gh repo view "${var.github_owner}/${var.fork_name}" &>/dev/null; then
        echo "Repository ${var.fork_name} already exists"
      else
        echo "Creating new repository..."
        # Create empty repository (not a fork)
        gh repo create "${var.github_owner}/${var.fork_name}" \
          --public \
          --description "Forked repo of Elastic's detection-rules, for a Purple Team presentation. An independent fork with cleaned history for demonstration purposes." \
          --clone=false

        echo "Cloning elastic/detection-rules source..."
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        git clone https://github.com/elastic/detection-rules.git
        cd detection-rules

        echo "Removing upstream remote..."
        git remote remove origin

        echo "Cleaning up unwanted GitHub Actions workflows..."
        # Run cleanup script from project root
        if [ -f "$(pwd)/../scripts/cleanup-workflows.sh" ]; then
          bash "$(pwd)/../scripts/cleanup-workflows.sh" .
        else
          echo "Warning: cleanup-workflows.sh not found, skipping workflow cleanup"
        fi

        echo "Creating clean history with orphan branch..."
        git checkout --orphan new-main
        git add -A
        git commit -m "Initial commit from elastic/detection-rules

This repository contains detection rules from Elastic Security for purple team demonstrations.
All rules are maintained as code and deployed via CI/CD."

        echo "Replacing main branch..."
        git branch -D main || true
        git branch -m main

        echo "Pushing to new repository..."
        git remote add origin "https://github.com/${var.github_owner}/${var.fork_name}.git"
        git push -f origin main

        echo "Cleaning up..."
        cd ../..
        rm -rf "$TEMP_DIR"

        echo "✅ Clean independent repository created successfully"
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Note: GitHub repository not automatically deleted"
      echo "To delete manually: gh repo delete ${self.triggers.github_owner}/${self.triggers.fork_name}"
      exit 0
    EOT
  }

  triggers = {
    github_owner = var.github_owner
    fork_name    = var.fork_name
  }
}

# Data source to access the forked repository information
data "github_repository" "detection_rules" {
  full_name = "${var.github_owner}/${var.fork_name}"

  depends_on = [null_resource.fork_detection_rules]
}
