#!/bin/bash
# Script to generate self-signed certificates for local development

# Get the hostname from the .env file or use the default
HOST_NAME=$(grep HOST_NAME .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")
HOST_NAME=${HOST_NAME:-iotpilot.test}

# Create directories if they don't exist
mkdir -p docker/traefik/config/certs

# Certificate paths
CERT_FILE="docker/traefik/config/certs/local-cert.pem"
KEY_FILE="docker/traefik/config/certs/local-key.pem"

# Check if certificates already exist
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    # Check certificate expiration
    if command -v openssl &> /dev/null; then
        EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
        # Convert to timestamp - compatible with both Linux and macOS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS date command
            EXPIRY_TIMESTAMP=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null)
        else
            # Linux date command
            EXPIRY_TIMESTAMP=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
        fi
        CURRENT_TIMESTAMP=$(date +%s)

        if [ -n "$EXPIRY_TIMESTAMP" ]; then
            # Calculate days until expiry
            DAYS_REMAINING=$(( ($EXPIRY_TIMESTAMP - $CURRENT_TIMESTAMP) / 86400 ))

            if [ $DAYS_REMAINING -gt 30 ]; then
                echo "Certificates already exist for $HOST_NAME and are valid for $DAYS_REMAINING more days."

                # Check if certificate's CN matches the current hostname
                CERT_CN=$(openssl x509 -noout -subject -in "$CERT_FILE" | grep -o "CN = [^,]*" | cut -d= -f2 | tr -d ' ')

                if [ "$CERT_CN" != "$HOST_NAME" ]; then
                    echo "Warning: Certificate was generated for $CERT_CN but your current hostname is $HOST_NAME."
                    echo "Consider regenerating with --force or update your hostname."
                else
                    # Exit early if no need to regenerate and no force flag
                    [ "$1" != "--force" ] && exit 0
                fi
            else
                echo "Certificates exist but will expire in $DAYS_REMAINING days. Regenerating..."
            fi
        else
            echo "Could not determine certificate expiration. Continuing with generation."
        fi
    else
        echo "OpenSSL not found. Cannot verify certificate. Continuing with generation."
    fi

    # If force flag is present, regenerate regardless
    if [ "$1" == "--force" ]; then
        echo "Force flag detected. Regenerating certificates..."
    fi
fi

echo "Generating new certificates for $HOST_NAME..."

# Generate certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$KEY_FILE" \
  -out "$CERT_FILE" \
  -subj "/CN=${HOST_NAME}/O=IoT Pilot/C=US" \
  -addext "subjectAltName = DNS:${HOST_NAME},DNS:*.${HOST_NAME},IP:127.0.0.1"

# Set permissions
chmod 644 "$CERT_FILE"
chmod 600 "$KEY_FILE"

echo "SSL certificate generated for ${HOST_NAME}"
echo "Use 'make install-cert' to install this certificate to your system trust store"