FROM alpine:3.22.8@sha256:9db293488671

RUN apk add --no-cache bash openssh-client curl jq iproute2 iputils bind-tools git make ca-certificates

WORKDIR /opt/zos
COPY . /opt/zos
RUN chmod +x /opt/zos/zOS/bin/zos /opt/zos/tools/*.sh

ENV OMEGA_ENV_FILE=/opt/zos/config/topology.env
ENTRYPOINT ["/opt/zos/zOS/bin/zos"]
CMD ["help"]
