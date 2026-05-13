#!/bin/bash

# App Foundry Suitability Agent Installer
# Installs the agent into Claude Code's agent directory

set -e

AGENT_NAME="appfoundry-suitability"
AGENT_DIR="$HOME/.claude/agents"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/agents/$AGENT_NAME.md"
TARGET_LINK="$AGENT_DIR/$AGENT_NAME.md"

echo "🚀 Installing App Foundry Suitability Agent..."
echo ""

# Check if Claude Code agent directory exists
if [ ! -d "$AGENT_DIR" ]; then
    echo "❌ Error: Claude Code agent directory not found at $AGENT_DIR"
    echo "   Make sure Claude Code is installed and you've run it at least once."
    exit 1
fi

# Check if source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Error: Agent source file not found at $SOURCE_FILE"
    exit 1
fi

# Remove existing symlink if it exists
if [ -L "$TARGET_LINK" ]; then
    echo "🔄 Removing existing agent symlink..."
    rm "$TARGET_LINK"
elif [ -f "$TARGET_LINK" ]; then
    echo "⚠️  Warning: A regular file exists at $TARGET_LINK"
    read -p "   Replace it with a symlink? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$TARGET_LINK"
    else
        echo "❌ Installation cancelled."
        exit 1
    fi
fi

# Create symlink
echo "🔗 Creating symlink: $TARGET_LINK -> $SOURCE_FILE"
ln -s "$SOURCE_FILE" "$TARGET_LINK"

echo ""
echo "✅ Installation complete!"
echo ""
echo "📚 Usage:"
echo "   1. Open any project in Claude Code"
echo "   2. Type: @appfoundry-suitability"
echo "   3. Ask: 'Can this app deploy to App Foundry?'"
echo ""
echo "   Or for new projects:"
echo "   Type: @appfoundry-suitability I want to build [describe app] for App Foundry"
echo ""
echo "🔍 The agent will analyze your codebase and provide:"
echo "   • Compatibility assessment"
echo "   • Critical blockers"
echo "   • Remediation plan"
echo "   • Timeline estimate"
echo ""
echo "For more information, see: $SCRIPT_DIR/README.md"
