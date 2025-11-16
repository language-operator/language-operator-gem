FROM ghcr.io/language-operator/base:latest

# Ruby dependencies inherited from base image

# Create application directory
WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile /app/

# Copy local gem if building in CI (will be downloaded from artifact)
# Use wildcard with --chown to avoid failure if file doesn't exist
COPY --chown=root:root language-operator-*.gem* /tmp/

# Install local gem first if it exists, then install bundle dependencies
RUN if ls /tmp/language-operator-*.gem 1> /dev/null 2>&1; then \
        echo "Installing local language-operator gem..." && \
        gem install /tmp/language-operator-*.gem && \
        rm /tmp/language-operator-*.gem*; \
    fi && \
    bundle install --no-cache

# Copy application files
COPY server.rb /app/
COPY lib/ /app/lib/

# Create /mcp directory for tool definitions
RUN mkdir -p /mcp && chown -R langop:langop /mcp

# Ensure app directory is owned by langop user
RUN chown -R langop:langop /app

# Expose default port
EXPOSE 80

# Set environment variables
ENV PORT=80
ENV RACK_ENV=production

# Switch to langop user
USER langop

# Start the server
CMD ["ruby", "server.rb"]
