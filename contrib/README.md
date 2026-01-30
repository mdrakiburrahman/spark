# Apache Spark Development Guide

Build Spark from source in WSL2/Ubuntu.

## Quick Start

```bash
# 1. Fresh WSL (Windows only)
wsl --unregister Ubuntu-24.04
wsl --install -d Ubuntu-24.04

# 2. Clone and open
cd ~/
git clone https://github.com/mdrakiburrahman/spark.git
cd spark && code .

# 3. Bootstrap (installs Java 17, Maven 3.9)
chmod +x contrib/bootstrap-dev-env.sh && ./contrib/bootstrap-dev-env.sh
source ~/.bashrc

# 4. Full build loop (clean → build → test → dist → docker)
chmod +x contrib/build-loop.sh && ./contrib/build-loop.sh

# 5. (Optional) Test SDP (Spark Declarative Pipelines)
chmod +x contrib/test-loop.sh && ./contrib/test-loop.sh
```

**Build time**: ~65 minutes (clean build on 8-core machine)

## What build-loop.sh Does

1. Cleans all state (target dirs, Maven cache, Zinc cache)
2. Builds all 37 modules with `-DskipTests -Phive -Phive-thriftserver`
3. Runs SparkPi smoke test
4. Creates distribution tarball
5. Builds Docker image (if Docker daemon running)
6. Verifies SDP (Spark Declarative Pipelines) components

Sample output:

```text
Summary:
  - Spark built successfully
  - Smoke test passed
  - Distribution created at: /home/mdrrahman/spark/dist
  - SDP (Spark Declarative Pipelines) components verified

Total time: 65m 35s

Next steps:
  - Start Spark shell: ./bin/spark-shell --master local[2]
  - Run more examples: ./bin/run-example <example-name>

To test SDP (Spark Declarative Pipelines):
  - Run: ./contrib/test-loop.sh
  - Or set TEST_SDP=1 ./contrib/build-loop.sh to include SDP test
```

## Testing SDP (Spark Declarative Pipelines)

SDP allows you to build declarative data pipelines. To test it:

```bash
# Option 1: Use the automated test script
./contrib/test-loop.sh

# Option 2: Manual step-by-step debugging

# Terminal 1: Start Spark Connect server
./sbin/start-connect-server.sh --wait --master local[4] \
    --conf spark.connect.grpc.binding.port=15002

# Terminal 2: Initialize and run a pipeline
./bin/spark-pipelines --remote sc://localhost:15002 init --name my-pipeline
cd my-pipeline
../bin/spark-pipelines --remote sc://localhost:15002 run --full-refresh-all
```

### SDP Architecture

- **Server**: Spark Connect (`sbin/start-connect-server.sh`)
- **Client CLI**: `bin/spark-pipelines`
- **Python Module**: `python/pyspark/pipelines/`
- **Scala Module**: `sql/pipelines/`

### Pipeline Spec Example

```yaml
name: my_pipeline
storage: file:///path/to/checkpoints
libraries:
  - glob:
      include: transformations/**
catalog: my_catalog
database: my_db
```

## Manual Commands

```bash
# Build only
./build/mvn -DskipTests clean install -Phive -Phive-thriftserver

# Smoke test
./bin/run-example SparkPi 10

# Create distribution
./dev/make-distribution.sh --name custom --pip --tgz -Phive -Phive-thriftserver

# Docker image
sudo ./bin/docker-image-tool.sh -r spark-docker -t latest build
```

## Troubleshooting

| Problem                  | Solution                                              |
| ------------------------ | ----------------------------------------------------- |
| `JAVA_HOME` not set      | `export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64` |
| Maven OOM                | `export MAVEN_OPTS="-Xmx4g"`                          |
| Docker permission denied | Run with `sudo`                                       |
| Spark Connect fails      | Check port 15002 is free: `lsof -i :15002`           |
| SDP "connection refused" | Start Spark Connect server first                      |
| PyYAML missing           | `pip3 install pyyaml`                                 |

## Files

- `bootstrap-dev-env.sh` - Installs Java 17, Maven 3.9, VS Code extensions
- `build-loop.sh` - Full build automation script
- `test-loop.sh` - SDP (Spark Declarative Pipelines) end-to-end test