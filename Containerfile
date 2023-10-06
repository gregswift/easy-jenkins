ARG SRC_IMAGE_NAME
ARG SRC_IMAGE_VERSION
ARG IMAGE_AUTHORS
ARG IMAGE_CREATED
ARG IMAGE_NAME
ARG IMAGE_REVISION
ARG IMAGE_REGISTRY
ARG IMAGE_SOURCE
ARG IMAGE_TITLE
ARG IMAGE_URL
ARG IMAGE_VERSION=${SRC_IMAGE_VERSION}

LABEL org.opencontainers.image.base.name ${IMAGE_REGISTRY}/${IMAGE_NAME}

LABEL org.opencontainers.image.authors ${IMAGE_AUTHORS}
LABEL org.opencontainers.image.created ${IMAGE_CREATED}
LABEL org.opencontainers.image.name ${IMAGE_NAME}
LABEL org.opencontainers.image.source ${IMAGE_SOURCE}
LABEL org.opencontainers.image.revision ${IMAGE_REVISION}
LABEL org.opencontainers.image.title ${IMAGE_TITLE}
LABEL org.opencontainers.image.url ${IMAGE_URL}
LABEL org.opencontainers.image.version ${IMAGE_VERSION}

FROM ${SRC_IMAGE_NAME}:${SRC_IMAGE_VERSION}

USER root

RUN apt-get update && apt-get install -y lsb-release

USER jenkins

COPY --chown=jenkins:jenkins plugins.txt /var/jenkins_home/plugins.txt

RUN jenkins-plugin-cli --plugin-file /var/jenkins_home/plugins.txt --latest false

ENV JAVA_OPTS "-Djenkins.install.runSetupWizard=false ${JAVA_OPTS:-}"
