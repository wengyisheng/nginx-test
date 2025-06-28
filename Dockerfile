# 第一阶段：下载文件和安装工具
FROM ubuntu:22.04 as downloader

# 设置环境变量以避免交互提示
ENV DEBIAN_FRONTEND=noninteractive

# 创建目录并安装必要的软件包
RUN mkdir -p /app/checkpoints && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    wget && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && \
    apt-get install -y google-cloud-sdk && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 使用 gsutil 从 Google Cloud Storage 下载文件
RUN gsutil -m cp -r gs://zhangyinghui-test/* /app/checkpoints/

# 第二阶段：构建最终镜像
FROM nginx:1.25-alpine

# 复制下载的文件
COPY --from=downloader /app/checkpoints /app/checkpoints

# 复制自定义HTML文件
COPY ./index.html /usr/share/nginx/html/index.html 

# 暴露端口
EXPOSE 80

# 设置停止信号
STOPSIGNAL SIGTERM

# 保持Nginx在前台运行
CMD ["nginx", "-g", "daemon off;"]
