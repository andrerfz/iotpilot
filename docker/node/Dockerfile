# docker/node/Dockerfile.raspberry
FROM arm32v6/node:14-alpine

# Set working directory
WORKDIR /app

# Install bash and nodemon
RUN apk add --no-cache bash && npm install -g nodemon@2.0.15

# Create entrypoint script
COPY docker/node/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose port
EXPOSE 4000

# Set entrypoint to use bash shell
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["npm", "run", "dev"]