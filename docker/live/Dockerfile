FROM python:3.12-slim
WORKDIR /workspace
COPY tools/live-gc-server.py /workspace/tools/
COPY docs/ /workspace/docs/
EXPOSE 8765
CMD ["python3", "/workspace/tools/live-gc-server.py", "--port", "8765"]
