FROM ghcr.io/innovanon-inc/python_dev_base_docker_image:latest

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

CMD ["dev_tree_watchdog"]

