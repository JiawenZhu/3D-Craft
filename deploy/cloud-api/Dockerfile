FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir 'fastapi>=0.115,<1' 'uvicorn>=0.32,<1' 'firebase-admin>=6.6,<8' 'python-dotenv>=1,<2' 'requests>=2.32,<3' 'google-cloud-tasks>=2.19,<3' 'Pillow>=11,<13' 'python-multipart>=0.0.20,<1' 'fal-client==0.14.1'
COPY server/__init__.py server/config.py server/identity.py server/firebase_studio.py server/firebase_api.py server/firebase_billing.py server/firebase_subscriptions.py server/firebase_webhooks.py server/account_deletion.py server/firebase_projects.py /app/server/
COPY server/firebase_usage.py server/cloud_model_provider.py server/firebase_model_jobs.py server/pricing.py server/commerce.py /app/server/
COPY server/firebase_community.py server/game_links.py server/cloud_planner_provider.py server/firebase_planning.py server/creative_prompts.py /app/server/
COPY server/cloud_concept_provider.py server/firebase_concepts.py /app/server/
COPY config/commerce/plans.json /app/config/commerce/plans.json
ENV RODIN_ENV=production RODIN_STORAGE=/tmp/craft/storage RODIN_RUNS=/tmp/craft/runs RODIN_EXPORTS=/tmp/craft/exports RODIN_WEIGHTS=/tmp/craft/weights RODIN_REPOS=/tmp/craft/vendor RODIN_INBOX=/tmp/craft/inbox
USER 65532:65532
CMD ["sh", "-c", "uvicorn server.firebase_api:app --host 0.0.0.0 --port ${PORT:-8080}"]
