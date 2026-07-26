# Ad-infinitum F2FS experiment lab (Linux only — requires privileged mode for F2FS mount)
FROM ubuntu:24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    f2fs-tools \
    fio \
    util-linux \
    mount \
    python3 \
    kmod \
    file \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY tools/ /workspace/tools/
COPY benchmarks/ /workspace/benchmarks/
COPY scripts/docker-lab-entrypoint.sh /usr/local/bin/lab-entrypoint.sh
RUN chmod +x /usr/local/bin/lab-entrypoint.sh /workspace/tools/*.sh 2>/dev/null || true

ENV MOUNT=/mnt/f2fs-test
ENTRYPOINT ["/usr/local/bin/lab-entrypoint.sh"]
