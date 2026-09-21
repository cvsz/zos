FROM alpine:3.22.6@sha256:abd29214470819ed7667c87c1ceebc89aae766453a5b3cc09e8a52b9f796fd5a

RUN apk add --no-cache bash openssh-client curl jq iproute2 iputils bind-tools git make ca-certificates

WORKDIR /opt/zos
COPY . /opt/zos
RUN chmod +x /opt/zos/zOS/bin/zos /opt/zos/tools/*.sh

ENV OMEGA_ENV_FILE=/opt/zos/config/topology.env
ENTRYPOINT ["/opt/zos/zOS/bin/zos"]
CMD ["help"]
