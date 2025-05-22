#!/bin/bash
set -e

# Define base project directory (two levels up from script location)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$PROJECT_DIR/app"
OUTPUT_DIR="$PROJECT_DIR/packages/arm64v8"

echo "📦 Building Node.js modules for Raspberry Pi 3 (ARM64/aarch64)..."
echo "🔍 Project directory: $PROJECT_DIR"
echo "🔍 App directory: $APP_DIR"
echo "🔍 Output directory: $OUTPUT_DIR"

# Check if package.json exists
if [ ! -f "$APP_DIR/package.json" ]; then
    echo "❌ Error: package.json not found at $APP_DIR/package.json"
    echo "  Current directory: $(pwd)"
    echo "  Please ensure the script is run from the docker/node directory"
    ls -la "$PROJECT_DIR"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create a temporary directory for the build
BUILD_DIR=$(mktemp -d)
echo "🔨 Using temporary build directory: $BUILD_DIR"

# Create the Dockerfile in the build directory
cat > "$BUILD_DIR/Dockerfile.arm64v8" << 'EOL'
# Use ARM64v8 Debian base image
FROM arm64v8/debian:bullseye

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    build-essential \
    python3 \
    make \
    g++ \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 16.x for ARM64 (matching the installer script)
RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - && \
    apt-get install -y nodejs && \
    npm --version

# Set working directory
WORKDIR /app

# Verify Node.js installation
RUN node --version && npm --version

# Copy package files
COPY package.json package-lock.json ./

# Set memory limit for Node to avoid crashes during build
ENV NODE_OPTIONS="--max-old-space-size=1024"

# Create data directory
RUN mkdir -p /app/data && chmod 777 /app/data

# Install dependencies in stages to avoid memory issues
RUN npm install --no-optional --no-save sqlite3 && \
    npm install --no-optional --no-save sequelize && \
    npm install --no-optional --no-save express && \
    npm install --no-optional --no-save better-sqlite3 || echo "Warning: better-sqlite3 may have issues on ARM64" && \
    npm install --no-optional

# Test only sqlite3 functionality (skip better-sqlite3 testing)
RUN node -e "try { \
    console.log('Testing SQLite3 for ARM64...'); \
    const sqlite3 = require('sqlite3'); \
    console.log('SQLite3 module loaded successfully:', sqlite3.VERSION); \
    const db = new sqlite3.Database(':memory:'); \
    db.serialize(() => { \
      db.run('CREATE TABLE test (id INT, name TEXT)'); \
      db.run('INSERT INTO test VALUES (1, \"test\")'); \
      db.each('SELECT * FROM test', (err, row) => { \
        console.log('SQLite3 test row:', row); \
      }); \
    }); \
    db.close(() => console.log('SQLite3 test successful!')); \
  } catch(e) { \
    console.error('SQLite3 test failed:', e); \
    process.exit(1); \
  }"

# Package the node_modules directory
ENTRYPOINT ["/bin/bash", "-c"]
CMD ["tar -czf /output/node_modules.tar.gz node_modules && cp package.json /output/ && echo 'Package successfully created!'"]
EOL

# Copy package.json and package-lock.json to the build directory
echo "📝 Copying package files to build directory..."
cp "$APP_DIR/package.json" "$APP_DIR/package-lock.json" "$BUILD_DIR/" || {
    echo "❌ Error copying package files. Ensure they exist at:"
    echo "  - $APP_DIR/package.json"
    echo "  - $APP_DIR/package-lock.json"
    exit 1
}

# Change to the build directory
cd "$BUILD_DIR"

# Setup Docker buildx for ARM emulation if running on x86
echo "🔄 Setting up Docker cross-platform support..."
docker run --privileged --rm tonistiigi/binfmt --install all
docker buildx create --name pi3-arm64-builder --driver docker-container --use || true
docker buildx inspect --bootstrap pi3-arm64-builder

# Build the image for ARM64
echo "🏗️ Building Docker image for ARM64..."
docker buildx build \
  --platform linux/arm64 \
  -t iotpilot-pi3-arm64-builder \
  -f Dockerfile.arm64v8 \
  --load \
  --progress=plain \
  .

# Run the container to create the tarball
echo "📦 Creating ARM64 node_modules package..."
docker run --platform linux/arm64 \
  -v "$OUTPUT_DIR:/output" \
  iotpilot-pi3-arm64-builder

# Create info file
cat > "$OUTPUT_DIR/build-info.txt" << EOL
IotPilot Build Information for ARM64
===================================
Date: $(date)
Target: Raspberry Pi 3 Model B (ARM64/aarch64)
Node.js: v16.x
Build System: Docker on $(uname -s) $(uname -m)

This package contains pre-compiled node_modules for Raspberry Pi 3 running 64-bit OS.
To install:
1. Copy node_modules.tar.gz to your Raspberry Pi 3
2. Extract with: tar -xzf node_modules.tar.gz -C /opt/iotpilot/app/
3. Fix permissions: sudo chown -R iotpilot:iotpilot /opt/iotpilot/app/node_modules
4. Restart service: sudo systemctl restart iotpilot

Note: better-sqlite3 might have compatibility issues on ARM64. The app will prefer sqlite3
when available.
EOL

# Clean up
echo "🧹 Cleaning up temporary files..."
rm -rf "$BUILD_DIR"

echo "✅ Build complete! ARM64 package saved to $OUTPUT_DIR/node_modules.tar.gz"
echo "📋 See $OUTPUT_DIR/build-info.txt for installation instructions"
echo ""
echo "This package is ONLY compatible with Raspberry Pi 3 or newer running 64-bit OS (aarch64)."
echo "It will NOT work on Raspberry Pi Zero or systems running 32-bit operating systems."