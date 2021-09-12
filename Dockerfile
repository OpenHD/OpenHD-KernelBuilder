FROM ubuntu:18.04

RUN apt-get update && apt-get install -y \
    bc\
    bison\
    build-essential\
    ccache\
    crossbuild-essential-armhf\
    flex\
    git\
    kmod\
    libelf-dev\
    libssl-dev\
    python3-pip\
    ruby    
    
RUN gem install --no-document fpm
RUN pip3 install --upgrade cloudsmith-cli

RUN ccache --set-config=compiler_check=content && ccache --set-config=hash_dir=false

ENV LD_LIBRARY_PATH "/usr/lib:${LD_LIBRARY_PATH}"

WORKDIR /kernelbuilder
