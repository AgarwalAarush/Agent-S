#!/bin/bash
# Setup script for grounding model server

set -e

ENV_NAME="grounding_model"

echo "Setting up UI-TARS Grounding Model Server..."
echo ""

# Check if conda is available
if ! command -v conda &> /dev/null; then
    echo "Error: conda is not installed or not in PATH"
    echo "Please install Anaconda or Miniconda first"
    exit 1
fi

# Check if conda environment exists
if conda env list | grep -q "^${ENV_NAME} "; then
    echo "Conda environment '${ENV_NAME}' already exists"
    echo "Activating existing environment..."
    eval "$(conda shell.bash hook)"
    conda activate ${ENV_NAME}
else
    echo "Creating conda environment '${ENV_NAME}'..."
    eval "$(conda shell.bash hook)"
    conda create -n ${ENV_NAME} python=3.10 -y
    conda activate ${ENV_NAME}
fi

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install dependencies
echo "Installing dependencies..."
pip install -r requirements.txt

# Create .env if it doesn't exist
if [ ! -f ".env" ]; then
    echo "Creating .env file..."
    cat > .env << 'EOF'
# Grounding Model Configuration

# Model configuration
GROUNDING_MODEL=ByteDance-Seed/UI-TARS-1.5-7B
DEVICE=cuda  # or "cpu" if no GPU available

# Server configuration
HOST=0.0.0.0
PORT=8080

# Backend URL for Agent S to connect to
# This is what Agent S will use to connect to the grounding model
GROUNDING_URL=http://localhost:8080
EOF
    echo "✓ .env file created"
else
    echo "✓ .env file already exists"
fi

echo ""
echo "Setup complete!"
echo ""
echo "To start the server, run:"
echo "  conda activate ${ENV_NAME}"
echo "  python server.py"
echo ""
echo "Or use:"
echo "  ./run.sh"
echo ""
echo "Note: Make sure conda is initialized in your shell"
echo "      Run: conda init <your-shell> if needed"
echo ""

