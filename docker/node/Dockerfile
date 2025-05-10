FROM node:16-slim

# Set working directory
WORKDIR /app

# Install nodemon globally
RUN npm install -g nodemon

# Copy entrypoint script
COPY docker/node/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose port
EXPOSE 4000

# Set the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["npm", "run", "dev"]