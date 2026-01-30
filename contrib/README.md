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
```

**Build time**: ~65 minutes (clean build on 8-core machine)

## What build-loop.sh Does

1. Cleans all state (target dirs, Maven cache, Zinc cache)
2. Builds all 37 modules with `-DskipTests -Phive -Phive-thriftserver`
3. Runs SparkPi smoke test
4. Creates distribution tarball
5. Builds Docker image (if Docker daemon running)

Sample output:

```text
Summary:
  - Spark built successfully
  - Smoke test passed
  - Distribution created at: /home/mdrrahman/spark/dist

Total time: 65m 35s

Next steps:
  - Start Spark shell: ./bin/spark-shell --master local[2]
  - Run more examples: ./bin/run-example <example-name>
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

## Files

- `bootstrap-dev-env.sh` - Installs Java 17, Maven 3.9, VS Code extensions
- `build-loop.sh` - Full build automation script