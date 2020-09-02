FROM ubuntu:20.04

RUN apt update && apt install -y stunnel

WORKDIR /stunnel

CMD [ "stunnel", "/stunnel/config/stunnel.conf" ]