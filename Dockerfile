FROM ubuntu:20.04
ENV DIR=/home/openhd/kernelbuilder

RUN apt-get update; \
    DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install tzdata; \
    apt-get install crossbuild-essential-armhf gcc-arm-linux-gnueabihf \
            crossbuild-essential-arm64 build-essential bc bison ccache git fakeroot \
            flex git kmod libelf-dev libssl-dev make python3-pip ruby-dev -y;

#Create Output Directory
RUN mkdir -p /out
RUN chmod 777 /out

RUN gem i fpm -f; 
RUN useradd -m openhd
USER openhd
RUN mkdir -p $DIR
WORKDIR $DIR

RUN ccache --set-config=compiler_check=content && ccache --set-config=hash_dir=false;

COPY . $DIR

CMD $DIR/dockerrun.sh