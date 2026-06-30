FROM docker.m.daocloud.io/library/node:22-alpine AS builder

ENV PNPM_HOME="/pnpm"
ENV PATH="${PNPM_HOME}:${PATH}"
ENV NODE_OPTIONS=--max-old-space-size=8192
ENV TZ=Asia/Shanghai
ENV CI=true
ENV HTTP_PROXY=
ENV HTTPS_PROXY=
ENV ALL_PROXY=
ENV http_proxy=
ENV https_proxy=
ENV all_proxy=

RUN corepack enable

WORKDIR /build

COPY yudao-ui/yudao-ui-admin-vben-temp/ /build/
COPY script/docker/frontend.env.production /build/apps/web-antd/.env.production

RUN --mount=type=cache,id=pnpm,target=/pnpm/store env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy pnpm install --frozen-lockfile
RUN env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy pnpm run build --filter=@vben/web-antd

FROM docker.m.daocloud.io/library/nginx:1.27-alpine

COPY script/docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /build/apps/web-antd/dist/ /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
