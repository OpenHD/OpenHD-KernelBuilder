FROM ubuntu:18.04

RUN apt-get update && apt-get install -y \
    bc\
    ccache\
    crossbuild-essential-armhf\
    git\
    python3-pip\
    ruby    

RUN gem install --no-document fpm
RUN pip3 install --upgrade cloudsmith-cli