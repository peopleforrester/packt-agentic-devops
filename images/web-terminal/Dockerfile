# ABOUTME: Browser web-terminal (ttyd) image for the Packt workshop student VTT. Glibc base (AWS CLI v2
# ABOUTME: has no musl build), full cluster/AWS toolset, Claude Code, the workshop repo pre-cloned.
FROM debian:bookworm-slim

# Base utilities the lab leans on. glibc base so AWS CLI v2 installs cleanly (it is not built for musl).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget unzip git jq less vim-tiny gnupg bash procps tmux \
 && rm -rf /var/lib/apt/lists/*

# ttyd (static binary), kubectl (pinned to the cluster minor 1.35), AWS CLI v2, helm, eksctl, k9s, yq.
# Arch-aware so the image builds on amd64 (the t3.2xlarge nodes) or arm64.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) TTYD=x86_64; AWS=x86_64; GOARCH=amd64 ;; \
      arm64) TTYD=aarch64; AWS=aarch64; GOARCH=arm64 ;; \
      *) echo "unsupported arch $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/ttyd "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TTYD}"; \
    chmod +x /usr/local/bin/ttyd; \
    KVER="$(curl -fsSL https://dl.k8s.io/release/stable-1.35.txt)"; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/${GOARCH}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL -o /tmp/awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-${AWS}.zip"; \
    unzip -q /tmp/awscli.zip -d /tmp; /tmp/aws/install; rm -rf /tmp/aws /tmp/awscli.zip; \
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; \
    curl -fsSL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_${GOARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin eksctl; \
    curl -fsSL "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${GOARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin k9s; \
    curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${GOARCH}"; \
    chmod +x /usr/local/bin/yq; \
    curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir /usr/local/bin; \
    kubectl version --client; aws --version; helm version --short; eksctl version; yq --version; starship --version

# The scoped student user. Numeric uid 1000 so the pod securityContext can verify runAsNonRoot.
RUN useradd -m -u 1000 -s /bin/bash student \
 && mkdir -p /home/student/.kube /home/student/.aws /home/student/.config \
 && chown -R student:student /home/student

# Starship prompt config + tmux config, baked in so the shell comes up pretty and persistent.
COPY starship.toml /home/student/.config/starship.toml
COPY tmux.conf /home/student/.tmux.conf

# ttyd launch shim: attaches each browser terminal to a named, persistent tmux session.
COPY vtt-shell /usr/local/bin/vtt-shell

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/vtt-shell \
 && chown student:student /home/student/.config/starship.toml /home/student/.tmux.conf

USER student
WORKDIR /home/student

# Claude Code, installed per the workshop's own install path (native installer -> ~/.local/bin). This is
# a pure-Claude-Code workshop: the CLI ships in the image, students authenticate with their OWN
# subscription on first `claude` run. No credentials are baked in.
RUN curl -fsSL https://claude.ai/install.sh | bash \
 && /home/student/.local/bin/claude --version

# The workshop repo, pre-cloned so a student lands with the materials already present. Public repo, so
# no credentials are needed at build or for a later `git pull`. entrypoint.sh refreshes it on start.
RUN git clone --depth 1 https://github.com/peopleforrester/packt-agentic-devops.git /home/student/workshop

# ttyd listens on 7681; the per-student router fronts it. Auth/exposure are handled upstream.
EXPOSE 7681
ENTRYPOINT ["/entrypoint.sh"]
