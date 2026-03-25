FROM ubuntu:24.04
ENV TZ America/New_York
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV JULIA_VERSION 1.12.5
ENV JULIA_NUM_THREADS 4
ENV QUARTO_VERSION 1.9.30

RUN apt-get update \
    && apt-get install -y wget \
    && apt-get install -y unzip \
    && apt-get install -y git \
    && apt-get install -y gnupg2 \
    && apt-get install -y curl
RUN cd /usr/local/bin \
    && mkdir quarto_dir \
    && cd quarto_dir \
    && wget -q https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.deb \
    && echo "67a36160d8501bef64bbf983a8a11e79d30c243024677d21533328fec6e7c400  quarto-${QUARTO_VERSION}-linux-amd64.deb" | sha256sum -c - \
    && apt-get install -y ./quarto-${QUARTO_VERSION}-linux-amd64.deb \
    && quarto add --no-prompt kapsner/authors-block
RUN curl -fsSL https://install.julialang.org | sh -s -- -y \
    && /root/.juliaup/bin/juliaup add $JULIA_VERSION \
    && ln -s /root/.julia/juliaup/julia-$JULIA_VERSION+0.x64.linux.gnu/bin/julia /usr/local/bin/julia
RUN julia -e 'using Pkg; Pkg.add(["Revise","IJulia"]); using IJulia; IJulia.installkernel("julia");' \
    && mkdir -p /root/.julia/config \
    && echo "using Revise" >> /root/.julia/config/startup.jl
RUN bash
