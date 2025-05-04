# Use official Node.js 18 slim image for smaller footprint
FROM node:18-slim

# Set working directory
WORKDIR /

# Copy application code
COPY ../app .

# Install dependencies
RUN npm install --production

# Expose port
EXPOSE 4000

# Start the app
CMD ["node", "server.js"]