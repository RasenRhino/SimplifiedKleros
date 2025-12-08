# ============================================
# SimpleKleros - Foundry Test Environment
# ============================================
# This Dockerfile sets up a complete Foundry
# environment so you can run tests without
# installing anything locally.
# ============================================

FROM ghcr.io/foundry-rs/foundry:latest

# Set working directory
WORKDIR /app

# Copy project files
COPY foundry.toml .
COPY src/ ./src/
COPY test/ ./test/
COPY lib/ ./lib/

# Build the contracts to verify everything works
RUN forge build

# Default: run all tests
ENTRYPOINT ["forge"]
CMD ["test", "-vv"]
