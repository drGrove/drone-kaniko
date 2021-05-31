# v1.6.0-debug
ARG EXECUTOR_DIGEST=fcccd2ab9f3892e33fc7f2e950c8e4fc665e7a4c66f6a9d70b300d7a2103592f
FROM gcr.io/kaniko-project/executor@sha256:$EXECUTOR_DIGEST

ENV HOME /root
ENV USER root
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG /kaniko/.docker/
ENV DOCKER_CREDENTIAL_GCR_CONFIG /kaniko/.config/gcloud/docker_credential_gcr_config.json

# add the wrapper which acts as a drone plugin
COPY plugin.sh /kaniko/plugin.sh
ENTRYPOINT [ "/kaniko/plugin.sh" ]
