# docker/node/Dockerfile
FROM node:18-slim

# Set working directory
WORKDIR /app

# Install nodemon globally
RUN npm install -g nodemon

# Expose port
EXPOSE 4000

# Set the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["npm", "run", "dev"]