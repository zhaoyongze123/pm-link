# Docker 部署说明

## 目标

这套脚本用于当前仓库的 OA/BPM 版本在本地构建镜像，并上传到 `192.168.1.107` 进行预览部署。

## 本地直接运行

```bash
cd /Users/mac/项目/若伊部署/script/docker
docker compose up -d --build
```

默认端口：

- 前端：`http://127.0.0.1:18080`
- 后端：`http://127.0.0.1:48080`
- MySQL：`127.0.0.1:13306`
- Redis：`127.0.0.1:16379`

## 部署到 192.168.1.107

```bash
cd /Users/mac/项目/若伊部署
bash script/docker/deploy-to-107.sh
```

脚本流程：

1. 本地执行 `mvn -pl yudao-server -am clean package -DskipTests`
2. 构建 `ruoyi-server:local` 和 `ruoyi-admin:local`
3. `docker save` 导出镜像 tar
4. 上传到 `192.168.1.107`
5. 在远端 `/home/daiwei/deployments/ruoyi-release` 执行 `docker compose up -d --no-build --force-recreate server admin`
6. 校验 `http://127.0.0.1:48080/actuator/health`

## 环境变量覆盖

可通过环境变量覆盖默认值，例如：

```bash
REMOTE_HOST=192.168.1.107 REMOTE_PASSWORD=000000 bash script/docker/deploy-to-107.sh
```
