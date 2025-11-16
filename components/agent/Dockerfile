FROM ghcr.io/language-operator/base:latest

# Install agent-specific packages (Ruby deps inherited from base)
RUN apk add --no-cache jq

WORKDIR /app/agent

# Copy Gemfile and install dependencies
COPY Gemfile /app/agent/

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

# Copy default agent configuration
COPY config/ /app/agent/config/

# Copy entrypoint script
COPY bin/langop-agent /usr/local/bin/langop-agent
RUN chmod +x /usr/local/bin/langop-agent

# Set ownership
RUN chown -R langop:langop /app/agent

# Switch to langop user
USER langop

# Set environment defaults
ENV WORKSPACE_PATH="/workspace" \
    AGENT_MODE="autonomous" \
    AGENT_CODE_PATH="/etc/agent/code/agent.rb" \
    AGENT_FALLBACK_MODE="error"

# Default command - auto-loads synthesized code from ConfigMap
CMD ["/usr/local/bin/langop-agent"]
