FROM python:3.12-slim-bookworm

ENV POETRY_VIRTUALENVS_CREATE=false \
    PYTHONPATH=/workspace/tools/generated_proto \
    PYTHONUNBUFFERED=1

WORKDIR /workspace

RUN pip install --no-cache-dir poetry==1.8.2

COPY python ./python
COPY tools/python_quality.sh ./tools/python_quality.sh
COPY tools/generated_proto ./tools/generated_proto

RUN poetry install --directory python --no-root \
    && bash tools/python_quality.sh

CMD ["python", "python/adapters/pytorch-python/pytorch_python_adapter.py"]
