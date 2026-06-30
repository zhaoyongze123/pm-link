FROM docker.m.daocloud.io/library/eclipse-temurin:17-jre

WORKDIR /app

COPY yudao-server/target/yudao-server.jar /app/app.jar

ENV TZ=Asia/Shanghai
ENV JAVA_OPTS="-Xms512m -Xmx1024m -Djava.security.egd=file:/dev/./urandom"
ENV ARGS=""

EXPOSE 48080

CMD ["sh", "-c", "java ${JAVA_OPTS} -jar /app/app.jar --spring.profiles.active=${SPRING_PROFILES_ACTIVE:-local} ${ARGS}"]
