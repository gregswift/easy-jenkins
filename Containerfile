FROM jenkins/jenkins:lts-jdk17

USER root

RUN apt-get update && apt-get install -y lsb-release

# Why exactly do we need this ?
#RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
#  https://download.docker.com/linux/debian/gpg
#
#RUN echo "deb [arch=$(dpkg --print-architecture) \
#  signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
#  https://download.docker.com/linux/debian \
#  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
#
#RUN apt-get update && apt-get install -y docker-ce-cli

USER jenkins

COPY --chown=jenkins:jenkins artifacts/plugins.yaml /var/jenkins_home/plugins.yaml

RUN jenkins-plugin-cli --plugin-file /var/jenkins_home/plugins.yaml --latest false

ENV JAVA_OPTS "-Djenkins.install.runSetupWizard=false ${JAVA_OPTS:-}"
