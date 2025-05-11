#!/bin/bash
set -e

# Define application directory
APP_DIR="./app"

# Define output directory
OUTPUT_DIR="$(pwd)/packages/armv6"
mkdir -p "$OUTPUT_DIR"

echo "📦 Building Node.js modules for Raspberry Pi Zero (ARMv6)..."
echo "🔍 App directory: $APP_DIR"

# Create a temporary directory for the build
BUILD_DIR=$(mktemp -d)
echo "🔨 Using temporary build directory: $BUILD_DIR"

# Create the Dockerfile in the build directory
cat > "$BUILD_DIR/Dockerfile.armv6" << 'EOL'
# Use Balena's base image which supports ARMv6
FROM balenalib/raspberry-pi-debian:buster

# Install Node.js 16.x
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 16.x for ARMv6
RUN curl -fsSL https://unofficial-builds.nodejs.org/download/release/v16.20.2/node-v16.20.2-linux-armv6l.tar.xz | \
    tar -xJ -C /usr/local --strip-components=1

# Set working directory
WORKDIR /app

# Verify Node.js installation
RUN node --version && npm --version

# Copy package files
COPY package.json package-lock.json ./

# Set memory limit for Node to avoid crashes during build
ENV NODE_OPTIONS="--max-old-space-size=512" \
    NPM_CONFIG_LOGLEVEL=verbose

# Install dependencies
RUN npm config set unsafe-perm true
RUN npm install --no-optional --no-audit --no-fund

# Create data directory
RUN mkdir -p /app/data && chmod 777 /app/data

# Test SQLite functionality
RUN node -e "try { \
    console.log('Testing SQLite...'); \
    const sqlite3 = require('sqlite3'); \
    console.log('SQLite3 module loaded successfully:', sqlite3.VERSION); \
    const db = new sqlite3.Database(':memory:'); \
    db.serialize(() => { \
      db.run('CREATE TABLE test (id INT, name TEXT)'); \
      db.run('INSERT INTO test VALUES (1, \"test\")'); \
      db.each('SELECT * FROM test', (err, row) => { \
        console.log('SQLite test row:', row); \
      }); \
    }); \
    db.close(() => console.log('SQLite test successful!')); \
  } catch(e) { \
    console.error('SQLite test failed:', e); \
    process.exit(1); \
  }"

# Package the node_modules directory
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["tar -czf /output/node_modules.tar.gz node_modules && cp package.json /output/ && echo 'Package successfully created!'"]
EOL

# Change to the build directory
cd "$BUILD_DIR"

# Setup Docker buildx for ARM emulation
echo "🔄 Setting up Docker cross-platform support..."
docker run --privileged --rm tonistiigi/binfmt --install all
docker buildx create --name pi-builder --driver docker-container --use || true
docker buildx inspect --bootstrap pi-builder

# Build the image
echo "🏗️ Building Docker image for ARMv6..."
docker buildx build \
  --platform linux/arm/v6 \
  -t iotpilot-pi-zero-builder \
  -f Dockerfile.armv6 \
  --load \
  --progress=plain \
  .

# Run the container to create the tarball
echo "📦 Creating node_modules package..."
docker run --platform linux/arm/v6 \
  -v "$OUTPUT_DIR:/output" \
  iotpilot-pi-zero-builder

# Create info file
cat > "$OUTPUT_DIR/build-info.txt" << EOL
IotPilot Build Information
=========================
Date: $(date)
Target: Raspberry Pi Zero (ARMv6)
Node.js: v16.20.2
Build System: Docker on $(uname -s) $(uname -m)

This package contains pre-compiled node_modules for Raspberry Pi Zero.
To install:
1. Copy node_modules.tar.gz to your Raspberry Pi
2. Extract with: tar -xzf node_modules.tar.gz -C /opt/iotpilot/app/
3. Fix permissions: sudo chown -R iotpilot:iotpilot /opt/iotpilot/app/node_modules
4. Restart service: sudo systemctl restart iotpilot
EOL

# Clean up
echo "🧹 Cleaning up temporary files..."
rm -rf "$BUILD_DIR"

echo "✅ Build complete! Package saved to $OUTPUT_DIR/node_modules.tar.gz"
echo "📋 See $OUTPUT_DIR/build-info.txt for installation instructions"