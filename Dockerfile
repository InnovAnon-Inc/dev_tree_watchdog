FROM python:3.13-slim

# TODO it's okay use use all the build deps, so as to create a common layer
RUN apt-get update                             \
&&  apt-get install -y --no-install-recommends \
    gcc                                        \
    libc6-dev                                  \
&&  rm -rf /var/lib/apt/lists/*

# FIXME we have requirements.txt for a reason. we also have pyproject.toml dev deps
RUN pip install --no-cache-dir \
    dotenv                     \
    gitpython                  \
    PyGithub                   \
    watchdog

COPY . /app
WORKDIR /app
ENV SETUPTOOLS_SCM_PRETEND_VERSION_FOR_DEV_TREE_WATCHDOG=0.0.0

# TODO install build deps
# TODO build wheel

ENV PYTHONPATH="/app"

ENTRYPOINT ["python", "-u", "-m", "dev_tree_watchdog"]

