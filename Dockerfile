# ========================================
# Build Stage
# ========================================
# hugomods/hugo:exts hỗ trợ Hugo Extended mới nhất (compatible với Blowfish theme)
FROM hugomods/hugo:exts-0.159.2 AS builder

WORKDIR /src
COPY . .

RUN hugo --minify --gc

# ========================================
# Production Stage (Distroless)
# ========================================
FROM cgr.dev/chainguard/nginx:latest

COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080
