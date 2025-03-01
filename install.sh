#!/usr/bin/env bash
#
# SSHistorian - Installation Script
# Set up SSHistorian system-wide with all dependencies
#

set -eo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Function to print colored messages
print_message() {
    local level="$1"
    local message="$2"
    
    case "$level" in
        "info")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "success")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "error")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        *)
            echo -e "$message"
            ;;
    esac
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        # Detect distribution
        if [ -f /etc/debian_version ]; then
            DISTRO="debian"
        elif [ -f /etc/redhat-release ]; then
            DISTRO="redhat"
        else
            DISTRO="unknown"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        DISTRO=""
    else
        OS="unknown"
        DISTRO="unknown"
    fi
    
    print_message "info" "Detected OS: $OS ${DISTRO:+($DISTRO)}"
}

# Check dependencies
check_dependencies() {
    print_message "info" "Checking for required dependencies..."
    local missing_deps=()
    
    # Check for SQLite
    if ! command -v sqlite3 &>/dev/null; then
        missing_deps+=("sqlite3")
    fi
    
    # Check for OpenSSL
    if ! command -v openssl &>/dev/null; then
        missing_deps+=("openssl")
    fi
    
    # Check for util-linux tools (scriptreplay)
    if ! command -v scriptreplay &>/dev/null; then
        missing_deps+=("util-linux")
    fi
    
    # Check for TermRecord (optional)
    if ! command -v TermRecord &>/dev/null && ! python3 -c "import TermRecord" &>/dev/null 2>&1; then
        print_message "warning" "TermRecord is not installed. HTML playback will not be available."
        print_message "info" "You can install it later with: pip3 install TermRecord"
    fi
    
    # Install missing dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_message "info" "Installing missing dependencies: ${missing_deps[*]}"
        
        if [[ "$OS" == "linux" && "$DISTRO" == "debian" ]]; then
            sudo apt-get update
            sudo apt-get install -y "${missing_deps[@]}"
        elif [[ "$OS" == "linux" && "$DISTRO" == "redhat" ]]; then
            sudo yum install -y "${missing_deps[@]}"
        elif [[ "$OS" == "macos" ]]; then
            # Check if Homebrew is installed
            if ! command -v brew &>/dev/null; then
                print_message "error" "Homebrew not found. Please install Homebrew first: https://brew.sh/"
                exit 1
            fi
            brew install "${missing_deps[@]}"
        else
            print_message "error" "Unsupported OS for automatic dependency installation. Please install these dependencies manually: ${missing_deps[*]}"
            exit 1
        fi
    else
        print_message "success" "All required dependencies are installed."
    fi
}

# Install SSHistorian
install_sshistorian() {
    print_message "info" "Installing SSHistorian..."
    
    # Make the main script executable
    chmod +x "$SCRIPT_DIR/bin/sshistorian"
    
    # Create required directories
    mkdir -p "$SCRIPT_DIR/data/logs" 2>/dev/null || true
    chmod 700 "$SCRIPT_DIR/data" "$SCRIPT_DIR/data/logs" 2>/dev/null || true
    
    # Create encryption keys directory
    mkdir -p "$HOME/.config/sshistorian/keys" 2>/dev/null || true
    chmod 700 "$HOME/.config/sshistorian/keys" 2>/dev/null || true
    
    # Symlink to /usr/local/bin (or similar)
    local symlink_path="/usr/local/bin/sshistorian"
    
    # Check if symlink already exists
    if [ -L "$symlink_path" ]; then
        print_message "info" "Removing existing symlink: $symlink_path"
        sudo rm "$symlink_path"
    fi
    
    print_message "info" "Creating symlink: $symlink_path -> $SCRIPT_DIR/bin/sshistorian"
    sudo ln -s "$SCRIPT_DIR/bin/sshistorian" "$symlink_path"
    
    print_message "success" "SSHistorian installed successfully!"
}

# Generate encryption keys
generate_keys() {
    print_message "info" "Would you like to generate encryption keys now? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        print_message "info" "Generating encryption keys..."
        "$SCRIPT_DIR/bin/sshistorian" generate-keys
    else
        print_message "info" "Skipping key generation. You can generate keys later with: sshistorian generate-keys"
    fi
}

# Print installation summary
print_summary() {
    echo ""
    echo -e "${BOLD}SSHistorian Installation Complete${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    echo -e "Commands:"
    echo -e "  ${GREEN}sshistorian user@host${NC} - Start an SSH session with recording"
    echo -e "  ${GREEN}sshistorian sessions${NC} - List recorded sessions"
    echo -e "  ${GREEN}sshistorian replay <uuid>${NC} - Replay a recorded session"
    echo -e "  ${GREEN}sshistorian help${NC} - Show all available commands"
    echo ""
    echo -e "Documentation:"
    echo -e "  ${BLUE}$SCRIPT_DIR/docs/user_guide/README.md${NC} - User Guide"
    echo -e "  ${BLUE}$SCRIPT_DIR/docs/security/README.md${NC} - Security Documentation"
    echo ""
    echo -e "For more information, visit: ${BOLD}https://github.com/maiko/sshistorian${NC}"
    echo ""
}

# Main installation flow
main() {
    echo -e "${BOLD}${BLUE}SSHistorian Installation${NC}${BOLD}"
    echo -e "==============================${NC}"
    echo ""
    
    detect_os
    check_dependencies
    install_sshistorian
    generate_keys
    print_summary
}

main