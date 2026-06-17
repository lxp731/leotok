#!/bin/bash
# One-time setup for Termux backend.
# Run this after git pull or fresh clone.

set -e

if [ ! -d ".venv" ]; then
    echo '📦 Creating virtual environment...'
    uv venv --python python3.13
    source .venv/bin/activate

    echo '📦 Installing dependencies...'
    uv pip install -r requirements.txt

    echo '✅ Setup complete. Start with: python server.py'
else
    echo "✅ Backend environment already set up. Skipping."
fi

# Configure start_server.sh with the actual project path
BACKEND_DIR="$(pwd)"
sed -i "s|^BACKEND_DIR=\"\"|BACKEND_DIR=\"$BACKEND_DIR\"|" start_server.sh
echo "✅ Configured start_server.sh with BACKEND_DIR=$BACKEND_DIR"

exit 0