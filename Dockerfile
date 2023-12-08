FROM golang:1.21 as dlv

RUN CGO_ENABLED=0 GOBIN=/ go install -ldflags "-s -w -extldflags '-static'" github.com/go-delve/delve/cmd/dlv@latest

# we need to use a distroless image that contains sh command.
FROM gcr.io/distroless/python3-debian11

ARG SERVICE

# this is the service binary
COPY ./bin/${SERVICE} /entry
# dlv is the debugger binary
COPY --from=dlv /dlv /
# debug.sh is the script that will run the debugger with the arguments passed to the container
COPY debug.sh /debug.sh

EXPOSE 4567

ENTRYPOINT [ "sh", "/debug.sh" ]

