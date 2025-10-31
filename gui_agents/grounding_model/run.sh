#!/bin/bash
# Run script for grounding model server

set -e

ENV_NAME="grounding_model"

# Check if conda is available
if ! command -v conda &> /dev/null; then
    echo "Error: conda is not installed or not in PATH"
    echo "Please install Anaconda or Miniconda first"
    exit 1
fi

# Initialize conda in bash shell
eval "$(conda shell.bash hook)"

# Check if conda environment exists
if ! conda env list | grep -q "^${ENV_NAME} "; then
    echo "Conda environment '${ENV_NAME}' not found. Running setup..."
    ./setup.sh
else
    # Activate conda environment
    echo "Activating conda environment '${ENV_NAME}'..."
    conda activate ${ENV_NAME}
fi

# Load environment variables
if [ -f ".env" ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Start the server
echo "Starting UI-TARS grounding model server..."
echo "Server will be available at http://localhost:${PORT:-8080}"
echo ""

python server.py

