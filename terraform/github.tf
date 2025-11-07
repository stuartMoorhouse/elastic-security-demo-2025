# Fork elastic/detection-rules repository
resource "null_resource" "fork_detection_rules" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Creating fork of elastic/detection-rules..."

      # Check if fork already exists
      if gh repo view "${var.github_owner}/${var.fork_name}" &>/dev/null; then
        echo "Fork ${var.fork_name} already exists"
      else
        echo "Creating fork..."
        gh repo fork elastic/detection-rules --fork-name="${var.fork_name}" --clone=false
        echo "Fork created successfully"
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Note: GitHub fork not automatically deleted"
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
