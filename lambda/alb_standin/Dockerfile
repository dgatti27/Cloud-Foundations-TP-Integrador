FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir flask boto3
COPY app.py .
ENV PORT=8088
EXPOSE 8088
CMD ["python", "app.py"]
