#!/bin/bash
set -e

# Script to remove unwanted GitHub Actions workflows from the detection-rules fork
# This removes elastic's workflows and keeps only our custom ones

REPO_DIR="${1:-.}"

echo "Cleaning up GitHub Actions workflows in: $REPO_DIR"

cd "$REPO_DIR/.github/workflows"

# List of workflows to KEEP
KEEP_WORKFLOWS=(
  "deploy-to-dev.yml"       # Our custom CI/CD workflow
  "pythonpackage.yml"       # Unit tests for Python code validation
  "code-checks.yml"         # Basic code quality checks
)

# Get all workflow files
ALL_WORKFLOWS=$(ls -1 *.yml *.yaml 2>/dev/null || true)

if [ -z "$ALL_WORKFLOWS" ]; then
  echo "No workflow files found"
  exit 0
fi

# Delete workflows not in the KEEP list
DELETED_COUNT=0
for workflow in $ALL_WORKFLOWS; do
  SHOULD_KEEP=false

  for keep in "${KEEP_WORKFLOWS[@]}"; do
    if [ "$workflow" = "$keep" ]; then
      SHOULD_KEEP=true
      break
    fi
  done

  if [ "$SHOULD_KEEP" = false ]; then
    echo "Removing: $workflow"
    rm "$workflow"
    ((DELETED_COUNT++))
  else
    echo "Keeping: $workflow"
  fi
done

echo ""

# Also remove/disable tests that check for deleted workflows
if [ -f "$REPO_DIR/tests/test_gh_workflows.py" ]; then
  echo "Removing workflow tests that reference deleted workflows..."
  rm "$REPO_DIR/tests/test_gh_workflows.py"
  echo "   Removed: tests/test_gh_workflows.py"
fi

echo ""
echo "✅ Cleanup complete!"
echo "   Deleted: $DELETED_COUNT workflows"
echo "   Kept: ${#KEEP_WORKFLOWS[@]} workflows"
echo "   Removed tests for deleted workflows"
