# builder
FROM debian:stable-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends nasm make binutils && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .
RUN make && strip build/mini-init-amd64

# runtime
FROM scratch
COPY --from=builder /src/build/mini-init-amd64 /mini-init-amd64
ENTRYPOINT ["/mini-init-amd64"]
