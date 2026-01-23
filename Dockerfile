FROM debian:bookworm-slim

# First apt step uses HTTP (works with ~/.docker/config.json proxy)
RUN apt update -y && apt upgrade -y && \
    apt install -y --no-install-recommends \
    make \
    git \
    ca-certificates \
    curl \
    jq \
    btop \
    sudo \
    zsh \
    iproute2 \
    procps \
    vim \
    xz-utils \
    net-tools \
    iputils-ping \
    dnsutils \
    tcpdump \
    telnet \
    unzip \
    openssl \
    wget \
    openssh-server && \
    rm -rf /var/lib/apt/lists/*

# Copy WSL related config and scripts
COPY --chmod=644 --chown=root:root ./wsl-distribution.conf /etc/wsl-distribution.conf
COPY --chmod=644 --chown=root:root ./wsl.conf /etc/wsl.conf
COPY --chmod=755 ./oobe.sh /etc/oobe.sh
COPY --chmod=755 ./oobe_linux.sh /etc/oobe_linux.sh
COPY ./eda_icon.ico /usr/lib/wsl/eda_icon.ico
COPY ./terminal-profile.json /usr/lib/wsl/terminal-profile.json

# Copy shell config files for oobe.sh to install
COPY --chmod=755 ./zsh/scripts/ /etc/zsh/scripts/
COPY --chmod=644 ./zsh/completions/ /etc/zsh/completions/
COPY --chmod=644 ./zsh/.zshrc /etc/zsh/.zshrc
COPY --chmod=644 ./zsh/starship.toml /etc/zsh/starship.toml
COPY --chmod=644 ./k9s/ /etc/k9s/

# SSH config
RUN bash -c "echo 'Port 2222' >> /etc/ssh/sshd_config"

# Apply sysctl settings for inotify (needed for file watchers, IDEs, etc.)
RUN mkdir -p /etc/sysctl.d && \
    echo -e "fs.inotify.max_user_watches=1048576\nfs.inotify.max_user_instances=512" > /etc/sysctl.d/90-wsl-inotify.conf

# Configure system-wide proxy (needed for sudo commands during build)
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
RUN if [ -n "$HTTP_PROXY" ]; then \
    printf 'Acquire::http::Proxy "%s";\n' "$HTTP_PROXY" > /etc/apt/apt.conf.d/proxy.conf && \
    printf 'Acquire::https::Proxy "%s";\n' "$HTTPS_PROXY" >> /etc/apt/apt.conf.d/proxy.conf && \
    printf 'export HTTP_PROXY="%s"\nexport HTTPS_PROXY="%s"\nexport NO_PROXY="%s"\nexport http_proxy="%s"\nexport https_proxy="%s"\nexport no_proxy="%s"\n' \
        "$HTTP_PROXY" "$HTTPS_PROXY" "$NO_PROXY" "$HTTP_PROXY" "$HTTPS_PROXY" "$NO_PROXY" >> /etc/environment && \
    echo 'Defaults env_keep += "HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy"' > /etc/sudoers.d/proxy; \
    fi

# Install Docker and clean up apt cache
RUN apt-get update && \
    curl -sL https://containerlab.dev/setup | bash -s "install-docker" && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Create eda user and add to sudo and docker groups
RUN useradd -m -s /bin/zsh eda && \
    echo "eda:eda" | chpasswd && \
    adduser eda sudo && \
    adduser eda docker && \
    echo "eda ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/eda && \
    chmod 0440 /etc/sudoers.d/eda

# Set eda as default user
ENV USER=eda
USER eda
WORKDIR /home/eda

# Install Starship prompt (pass proxy via sudo -E to preserve environment)
RUN curl -sS https://starship.rs/install.sh | sudo -E sh -s -- -y

# Create SSH key
RUN ssh-keygen -t ecdsa -b 256 -N "" -f ~/.ssh/id_ecdsa

# Install Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Install zsh plugins and clean up .git directories to save space
RUN git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone --depth 1 https://github.com/z-shell/F-Sy-H.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/F-Sy-H && \
    rm -rf ~/.oh-my-zsh/.git \
           ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions/.git \
           ~/.oh-my-zsh/custom/plugins/F-Sy-H/.git

# Copy shell configuration
COPY --chown=eda:eda ./zsh/.zshrc /home/eda/.zshrc
RUN mkdir -p /home/eda/.config
COPY --chown=eda:eda ./zsh/starship.toml /home/eda/.config/starship.toml

# VS Code machine settings (ensures zsh is default terminal in VS Code)
RUN mkdir -p /home/eda/.vscode-server/data/Machine
COPY --chown=eda:eda ./vscode-settings.json /home/eda/.vscode-server/data/Machine/settings.json

# Copy EDA configuration files and scripts
COPY --chmod=755 ./eda-up /usr/local/bin/eda-up
COPY --chmod=755 ./eda-vscode /usr/local/bin/eda-vscode
COPY --chmod=755 ./proxyman.sh /usr/local/bin/proxyman
COPY --chmod=644 ./eda/ /opt/eda/
