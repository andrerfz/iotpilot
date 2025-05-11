#!/bin/bash
# Script to install the SSL certificate to the system trust store

# Get the hostname from the .env file or use the default
HOST_NAME=$(grep HOST_NAME .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")
HOST_NAME=${HOST_NAME:-iotpilot.test}

# Certificate path
CERT_FILE="docker/traefik/config/certs/local-cert.pem"

# Check if certificate exists
if [ ! -f "$CERT_FILE" ]; then
    echo "Certificate not found! Run 'make generate-certs' first."
    exit 1
fi

# Detect operating system
OS="$(uname -s)"
case "${OS}" in
    Linux*)
        # Detect Linux distribution type
        if [ -f /etc/debian_version ]; then
            # Debian/Ubuntu based
            echo "Detected Debian/Ubuntu-based system"
            if [ -d /usr/local/share/ca-certificates ]; then
                echo "Installing certificate to system trust store..."
                sudo cp "$CERT_FILE" /usr/local/share/ca-certificates/iotpilot-local.crt
                sudo update-ca-certificates
                echo "Certificate installed successfully!"
            else
                echo "Error: CA certificates directory not found"
                exit 1
            fi
        elif [ -f /etc/redhat-release ]; then
            # RHEL/CentOS/Fedora
            echo "Detected RHEL/CentOS/Fedora system"
            sudo cp "$CERT_FILE" /etc/pki/ca-trust/source/anchors/iotpilot-local.crt
            sudo update-ca-trust extract
            echo "Certificate installed successfully!"
        else
            echo "Unsupported Linux distribution. Please install the certificate manually:"
            echo "1. Copy $CERT_FILE to your system's certificate store"
            echo "2. Run the appropriate command to update the certificate store"
            exit 1
        fi
        ;;
    Darwin*)
        # macOS
        echo "Detected macOS system"
        echo "Installing certificate to system trust store..."
        sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_FILE"
        echo "Certificate installed successfully! You may need to restart your browser."
        ;;
    MINGW*|CYGWIN*|MSYS*)
        # Windows with Git Bash or similar
        echo "Detected Windows system"
        echo "Windows certificate installation requires manual steps:"
        echo "1. Double-click on $CERT_FILE"
        echo "2. Select 'Install Certificate...'"
        echo "3. Select 'Local Machine' and click 'Next'"
        echo "4. Select 'Place all certificates in the following store' and click 'Browse'"
        echo "5. Select 'Trusted Root Certification Authorities' and click 'OK'"
        echo "6. Click 'Next' and then 'Finish'"
        echo ""
        echo "Would you like to open the certificate now? (y/n)"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            start "$CERT_FILE"
        fi
        ;;
    *)
        echo "Unknown operating system. Please install the certificate manually:"
        echo "1. Import $CERT_FILE into your system's certificate trust store"
        exit 1
        ;;
esac

echo "Certificate for $HOST_NAME installed to system trust store"
echo "You may need to restart your browser or applications to apply the changes"