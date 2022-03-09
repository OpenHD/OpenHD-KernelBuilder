FROM ubuntu:20.04

RUN apt-get update; \
    DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install tzdata; \
    apt-get install crossbuild-essential-armhf gcc-arm-linux-gnueabihf \
            crossbuild-essential-arm64 build-essential bc bison ccache git fakeroot \
            flex git kmod libelf-dev libssl-dev make python3-pip -y;

RUN useradd -m openhd
USER openhd
RUN mkdir -p /home/openhd/kernelbuilder
WORKDIR /home/openhd/kernelbuilder

RUN ccache --set-config=compiler_check=content && ccache --set-config=hash_dir=false;

COPY . /home/openhd/kernelbuilder

RUN bash