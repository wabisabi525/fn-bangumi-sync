FROM python:3.11-alpine
WORKDIR /app
ENV TZ=Asia/Shanghai
ENV DB_PATH=/db/trimmedia.db
COPY requirements.txt .
RUN pip install -r requirements.txt -i https://mirrors.cloud.tencent.com/pypi/simple/ --default-timeout=120 --no-cache-dir
COPY app.py .
COPY templates/ ./templates/
RUN touch synced.json
EXPOSE 5000
CMD ["python", "app.py"]
