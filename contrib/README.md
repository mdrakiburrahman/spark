# Apache Spark Development Guide

This guide explains how to set up a development environment, build Apache Spark from source, run tests, and create Docker images.

## Prerequisites

- **OS**: Ubuntu 22.04/24.04 (or WSL2 on Windows)
- **Java**: OpenJDK 17+
- **Maven**: 3.9+
- **Python**: 3.8+ (for PySpark)
- **Docker**: For containerization

## Quick Start (WSL2)

1. **Get a fresh WSL machine** (Windows only):

   ```powershell
   # Delete old WSL (if needed)
   wsl --unregister Ubuntu-24.04

   # Create new WSL
   wsl --install -d Ubuntu-24.04
   ```

2. **Clone the repo and open in VS Code**:

   ```bash
   cd ~/

   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   git clone https://github.com/mdrakiburrahman/spark.git

   cd spark/
   code .
   ```

3. **Run the bootstrap script** (installs Java 17, Maven 3.9, etc.):

   ```bash
   # Install beads task tracker (optional)
   curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash

   # Run bootstrap script
   GIT_ROOT=$(git rev-parse --show-toplevel)
   chmod +x ${GIT_ROOT}/contrib/bootstrap-dev-env.sh && ${GIT_ROOT}/contrib/bootstrap-dev-env.sh

   # Reload shell to pick up environment variables
   source ~/.bashrc
   ```

4. **Verify installation**:

   ```bash
   java -version    # Should show 17.x
   mvn -version     # Should show 3.9.x
   ```

## Build Spark

### Full Build (Skip Tests)

```bash
cd ${GIT_ROOT}
export MAVEN_OPTS="-Xmx4g"

# Build and install all modules
./build/mvn -DskipTests clean install -Phive -Phive-thriftserver
```

**Note**: First build takes ~45-50 minutes. Subsequent builds are faster due to Maven caching.

### Quick Build (Specific Module)

```bash
# Build only core module
mvn -pl core -DskipTests package

# Build SQL modules
mvn -pl sql/core,sql/catalyst -DskipTests package
```

## Run Smoke Test

Verify your build works correctly:

```bash
# Run SparkPi example
./bin/run-example SparkPi 10

# Expected output: "Pi is roughly 3.14..."
```

### Interactive Shell

```bash
# Start Spark shell
./bin/spark-shell --master local[2]

# In the shell:
# scala> spark.range(10).count()
# res0: Long = 10
# scala> :quit
```

## Run Unit Tests

```bash
# Run all tests (takes a long time)
mvn test

# Run tests for specific module
mvn test -pl core
mvn test -pl sql/core

# Run a single test class
mvn test -pl core -Dtest=SparkContextSuite
```

## Build Docker Image

1. **Create Spark distribution**:

   ```bash
   ./dev/make-distribution.sh --name custom --pip --tgz -Phive -Phive-thriftserver
   ```

2. **Build Docker image** (requires Docker to be running):

   ```bash
   # May need sudo for Docker access
   sudo ./bin/docker-image-tool.sh -r spark-docker -t latest build
   ```

3. **Verify image**:

   ```bash
   docker images | grep spark
   # spark-docker/spark   latest   ...   ~983MB
   ```

## Troubleshooting

| Problem                      | Solution                                              |
| ---------------------------- | ----------------------------------------------------- |
| `JAVA_HOME` not set          | `export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64` |
| Maven out of memory          | `export MAVEN_OPTS="-Xmx4g"`                          |
| Missing `protoc`             | `sudo apt install protobuf-compiler`                  |
| Docker permission denied     | Run with `sudo` or add user to docker group           |
| Build fails with test errors | Use `./build/mvn -DskipTests clean install`           |

## Files in This Directory

- `bootstrap-dev-env.sh` - Automated setup script for Java 17, Maven 3.9, VS Code extensions
- `README.md` - This file

## References

- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)
- [Building Spark](https://spark.apache.org/docs/latest/building-spark.html)
- [Docker Image Tool](https://spark.apache.org/docs/latest/running-on-kubernetes.html#docker-images)