FROM ubuntu:20.04

ARG userid=1000
ARG groupid=1000
ARG username=builder

ENV DEBIAN_FRONTEND=noninteractive

# AOSP build dependencies
RUN apt-get update && apt-get install -y \
    bc \
    bison \
    build-essential \
    ccache \
    curl \
    flex \
    g++-multilib \
    gcc-multilib \
    git \
    git-lfs \
    gnupg \
    gperf \
    imagemagick \
    lib32ncurses5-dev \
    lib32readline-dev \
    lib32z1-dev \
    libelf-dev \
    liblz4-tool \
    libncurses5 \
    libncurses5-dev \
    libsdl1.2-dev \
    libssl-dev \
    libxml2 \
    libxml2-utils \
    lzop \
    m4 \
    openjdk-11-jdk \
    pngcrush \
    python3 \
    python3-pip \
    rsync \
    schedtool \
    squashfs-tools \
    unzip \
    wget \
    xsltproc \
    zip \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install repo tool
RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo \
    && chmod a+x /usr/local/bin/repo

# Set up ccache
ENV USE_CCACHE=1
ENV CCACHE_DIR=/src/.ccache
ENV CCACHE_EXEC=/usr/bin/ccache

# Create user matching host UID/GID
RUN groupadd -g ${groupid} ${username} 2>/dev/null || true \
    && useradd -m -u ${userid} -g ${groupid} -s /bin/bash ${username} \
    && echo "${username} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Git config (needed for repo)
RUN git config --system user.email "builder@hydra.local" \
    && git config --system user.name "Hydra Builder" \
    && git config --system color.ui false

ENV HOME=/home/${username}
ENV USER=${username}
ENV PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOME}/bin

USER ${username}
WORKDIR /src
