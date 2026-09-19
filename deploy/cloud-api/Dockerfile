FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir 'fastapi>=0.115,<1' 'uvicorn>=0.32,<1' 'firebase-admin>=6.6,<8' 'python-dotenv>=1,<2' 'requests>=2.32,<3' 'google-cloud-tasks>=2.19,<3' 'Pillow>=11,<13' 'python-multipart>=0.0.20,<1' 'fal-client==0.14.1' 'httpx[http2]>=0.27,<1' 'cryptography>=43,<47'
# Every top-level server module, so adding one never breaks the image the
# way a hand-maintained file list did. The heavy local directories
# (runs, weights, storage, exports) are not matched by this glob.
COPY server/*.py /app/server/
COPY config/commerce/plans.json /app/config/commerce/plans.json
ENV RODIN_ENV=production RODIN_STORAGE=/tmp/craft/storage RODIN_RUNS=/tmp/craft/runs RODIN_EXPORTS=/tmp/craft/exports RODIN_WEIGHTS=/tmp/craft/weights RODIN_REPOS=/tmp/craft/vendor RODIN_INBOX=/tmp/craft/inbox
USER 65532:65532
CMD ["sh", "-c", "uvicorn server.firebase_api:app --host 0.0.0.0 --port ${PORT:-8080}"]
