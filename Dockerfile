# syntax=docker/dockerfile:1

ARG MISE_VERSION=2026.9.11
ARG CHEZMOI_VERSION=2.73.0
ARG DOCKER_VERSION=29.9.1
ARG CONTAINERD_VERSION=2.2.6
ARG BUILDX_VERSION=0.38.0
ARG COMPOSE_VERSION=5.6.0
ARG OH_MY_ZSH_COMMIT=964ddf789b022b6958b27d02d7fa54f552de21e9
ARG ZSH_AUTOSUGGESTIONS_COMMIT=85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5
ARG ZSH_SYNTAX_HIGHLIGHTING_COMMIT=e6683f20e5c38d3e5447f45845d04ddda75d0f23

FROM ghcr.io/jdx/mise:${MISE_VERSION} AS mise-image

FROM mcr.microsoft.com/devcontainers/base:bookworm

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
ARG CHEZMOI_VERSION
ARG DOCKER_VERSION
ARG CONTAINERD_VERSION
ARG BUILDX_VERSION
ARG COMPOSE_VERSION
ARG OH_MY_ZSH_COMMIT
ARG ZSH_AUTOSUGGESTIONS_COMMIT
ARG ZSH_SYNTAX_HIGHLIGHTING_COMMIT

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/${USERNAME} \
    LOGNAME=${USERNAME} \
    MISE_DATA_DIR=/home/${USERNAME}/.local/share/mise \
    MISE_CONFIG_DIR=/home/${USERNAME}/.config/mise \
    MISE_CACHE_DIR=/home/${USERNAME}/.cache/mise \
    MISE_STATE_DIR=/home/${USERNAME}/.local/state/mise \
    MISE_INSTALL_PATH=/usr/local/bin/mise \
    SHELL=/usr/bin/zsh \
    USER=${USERNAME} \
    PATH=/home/${USERNAME}/.local/share/mise/shims:/usr/local/bin:${PATH}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# OS foundation: packages expected in every shell, bootstrap, and diagnostics path.
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        autojump \
        ca-certificates \
        curl \
        fd-find \
        git \
        iputils-ping \
        jq \
        less \
        openssh-client \
        ripgrep \
        sudo \
        tar \
        unzip \
        vim \
        zsh

# Docker Engine runs as an independent daemon inside the privileged devbox.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl --fail --show-error --silent --location --retry 3 --retry-delay 2 \
        https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && printf '%s\n' \
        'Types: deb' \
        'URIs: https://download.docker.com/linux/debian' \
        'Suites: bookworm' \
        'Components: stable' \
        'Architectures: amd64' \
        'Signed-By: /etc/apt/keyrings/docker.asc' \
        > /etc/apt/sources.list.d/docker.sources
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce="5:${DOCKER_VERSION}-1~debian.12~bookworm" \
        docker-ce-cli="5:${DOCKER_VERSION}-1~debian.12~bookworm" \
        containerd.io="${CONTAINERD_VERSION}-1~debian.12~bookworm" \
        docker-buildx-plugin="${BUILDX_VERSION}-1~debian.12~bookworm" \
        docker-compose-plugin="${COMPOSE_VERSION}-1~debian.12~bookworm"

# Identity and home: keep the persistent container home writable by the dev user.
RUN if getent group "${USER_GID}" >/dev/null; then \
        EXISTING_GROUP="$(getent group "${USER_GID}" | cut -d: -f1)"; \
        groupmod --new-name "${USERNAME}" "${EXISTING_GROUP}"; \
    else \
        groupadd --gid "${USER_GID}" "${USERNAME}"; \
    fi \
    && if id --user "${USER_UID}" >/dev/null 2>&1; then \
        EXISTING_USER="$(getent passwd "${USER_UID}" | cut -d: -f1)"; \
        usermod --login "${USERNAME}" --home "/home/${USERNAME}" --move-home "${EXISTING_USER}"; \
        usermod --gid "${USER_GID}" --shell /usr/bin/zsh "${USERNAME}"; \
    else \
        useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /usr/bin/zsh "${USERNAME}"; \
    fi \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}" \
    && usermod --append --groups docker "${USERNAME}" \
    && mkdir -p "/home/${USERNAME}/items" "/home/${USERNAME}/.dev-env/state" \
        "/home/${USERNAME}/.cache" "/home/${USERNAME}/.local" "/home/${USERNAME}/.config" \
    && chown -R "${USER_UID}:${USER_GID}" "/home/${USERNAME}"

# Project tool manager layer: project runtimes and tasks belong in per-repo mise.toml.
COPY --from=mise-image /usr/local/bin/mise /usr/local/bin/mise
RUN mise --version

# Shell layer: keep the Oh My Zsh distribution and plugins in the image so the
# persistent home volume cannot replace the repository-owned shell baseline.
RUN git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git /usr/local/share/oh-my-zsh \
    && cd /usr/local/share/oh-my-zsh \
    && git fetch --depth 1 origin "${OH_MY_ZSH_COMMIT}" \
    && git checkout --detach "${OH_MY_ZSH_COMMIT}" \
    && git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions.git \
        /usr/local/share/oh-my-zsh/custom/plugins/zsh-autosuggestions \
    && cd /usr/local/share/oh-my-zsh/custom/plugins/zsh-autosuggestions \
    && git fetch --depth 1 origin "${ZSH_AUTOSUGGESTIONS_COMMIT}" \
    && git checkout --detach "${ZSH_AUTOSUGGESTIONS_COMMIT}" \
    && git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
        /usr/local/share/oh-my-zsh/custom/plugins/zsh-syntax-highlighting \
    && cd /usr/local/share/oh-my-zsh/custom/plugins/zsh-syntax-highlighting \
    && git fetch --depth 1 origin "${ZSH_SYNTAX_HIGHLIGHTING_COMMIT}" \
    && git checkout --detach "${ZSH_SYNTAX_HIGHLIGHTING_COMMIT}"
COPY config/zsh/.zshrc /usr/local/share/dev-env/zshrc

# Dotfiles manager layer: install chezmoi for non-shell personal files.
RUN curl --fail --show-error --silent --location --retry 3 --retry-delay 2 --http1.1 \
        "https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux-glibc_amd64.tar.gz" \
        | tar --extract --gzip --directory /usr/local/bin chezmoi \
    && chmod +x /usr/local/bin/chezmoi \
    && chezmoi --version

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh \
    && docker --version \
    && docker compose version \
    && docker buildx version

USER ${USERNAME}
WORKDIR /home/${USERNAME}

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
