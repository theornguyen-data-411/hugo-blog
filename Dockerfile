# ========================================
# Build Stage
# ========================================
FROM klakegg/hugo:ext-alpine AS builder

WORKDIR /src
COPY . .

RUN hugo --minify --gc

# ========================================
# Production Stage (Distroless)
# ========================================
FROM cgr.dev/chainguard/nginx:latest

COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080
