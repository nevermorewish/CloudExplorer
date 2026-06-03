# syntax=docker/dockerfile:1.4

FROM registry.cn-qingdao.aliyuncs.com/cloudexplorer/alpine-openjdk17:latest AS builder

ARG APP_VERSION=main

WORKDIR /workspace

RUN apk add --no-cache nodejs \
    && mkdir -p node/yarn/dist/bin \
    && ln -sf /usr/bin/node node/node \
    && printf '#!/bin/sh\nexec /usr/bin/node /workspace/.yarn/releases/yarn-3.5.1.cjs "$@"\n' > node/yarn/dist/bin/yarn \
    && printf '#!/bin/sh\nexec /usr/bin/node /workspace/.yarn/releases/yarn-3.5.1.cjs "$@"\n' > node/yarn/dist/bin/yarnpkg \
    && chmod +x node/yarn/dist/bin/yarn node/yarn/dist/bin/yarnpkg \
    && node/node --version

RUN mkdir -p /root/.m2 \
    && printf '%s\n' \
        '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 https://maven.apache.org/xsd/settings-1.0.0.xsd">' \
        '  <mirrors>' \
        '    <mirror>' \
        '      <id>aliyun-public</id>' \
        '      <mirrorOf>central</mirrorOf>' \
        '      <name>Aliyun Maven Public</name>' \
        '      <url>https://maven.aliyun.com/repository/public</url>' \
        '    </mirror>' \
        '  </mirrors>' \
        '</settings>' \
        > /root/.m2/settings.xml

COPY . .

RUN sed -i 's/\r$//' mvnw \
    && sed -i 's#^distributionUrl=.*#distributionUrl=https://archive.apache.org/dist/maven/maven-3/3.8.8/binaries/apache-maven-3.8.8-bin.zip#' .mvn/wrapper/maven-wrapper.properties \
    && chmod +x mvnw

RUN --mount=type=cache,target=/root/.m2/repository \
    ./mvnw -B -N org.apache.maven.plugins:maven-install-plugin:3.1.1:install-file -Dfile=framework/provider/lib/vmware/vapi-runtime-2.34.0.jar -DgroupId=com.vmware.vapi -DartifactId=vapi-runtime -Dversion=2.34.0 -Dpackaging=jar \
    && ./mvnw -B -N org.apache.maven.plugins:maven-install-plugin:3.1.1:install-file -Dfile=framework/provider/lib/vmware/vapi-authentication-2.34.0.jar -DgroupId=com.vmware.vapi -DartifactId=vapi-authentication -Dversion=2.34.0 -Dpackaging=jar \
    && ./mvnw -B -N org.apache.maven.plugins:maven-install-plugin:3.1.1:install-file -Dfile=framework/provider/lib/vmware/vapi-samltoken-2.34.0.jar -DgroupId=com.vmware.vapi -DartifactId=vapi-samltoken -Dversion=2.34.0 -Dpackaging=jar \
    && ./mvnw -B -N org.apache.maven.plugins:maven-install-plugin:3.1.1:install-file -Dfile=framework/provider/lib/vmware/vsphereautomation-client-sdk-3.9.0.jar -DgroupId=com.vmware -DartifactId=vsphereautomation-client-sdk -Dversion=3.9.0 -Dpackaging=jar

RUN find framework services demo -path '*/frontend/pom.xml' -exec sed -i '/<nodeVersion>${node.version}<\/nodeVersion>/i\              <skip>true</skip>' {} \;

RUN --mount=type=cache,target=/root/.m2/repository \
    ./mvnw -B -Drevision="${APP_VERSION}" -DskipTests -pl framework/eureka,framework/sdk/frontend,framework/gateway,framework/management-center/frontend,framework/management-center/backend -am install

FROM registry.cn-qingdao.aliyuncs.com/cloudexplorer/alpine-openjdk17:latest

LABEL maintainer="FIT2CLOUD <support@fit2cloud.com>"

ARG APP_VERSION=main

WORKDIR /opt/cloudexplorer/apps/core/repository
COPY --from=builder /workspace/target/repository ./

WORKDIR /opt/cloudexplorer/apps/core
COPY --from=builder /workspace/doc/cloudexplorer/apps/core/run-core.sh ./
RUN chmod 755 run-core.sh \
    && ln -s /opt/cloudexplorer/apps/core/run-core.sh /usr/bin/run-core \
    && mkdir -p /opt/cloudexplorer/downloads \
    && mkdir -p /opt/cloudexplorer/apps/extra

COPY --from=builder /workspace/target/eureka-${APP_VERSION}.jar ./
COPY --from=builder /workspace/target/gateway-${APP_VERSION}.jar ./
COPY --from=builder /workspace/target/management-center-${APP_VERSION}.jar ./

WORKDIR /opt/cloudexplorer
RUN echo "${APP_VERSION}" > VERSION

CMD ["run-core", "run"]
