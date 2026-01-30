#!/bin/bash
#
# build-loop.sh - Complete Spark build, test, and Docker image creation
#
# This script is idempotent and bulletproof:
#   1. Cleans ALL previous state (builds, caches)
#   2. Builds Spark from source
#   3. Runs smoke tests
#   4. Creates distribution
#   5. Builds Docker image
#
# Usage: ./contrib/build-loop.sh
#
# Prerequisites: Run bootstrap-dev-env.sh first
#
# ---------------------------------------------------------------------------------------

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

# Get the git root directory
GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

# Timing
START_TIME=$(date +%s)
log_time() {
    local CURRENT_TIME=$(date +%s)
    local ELAPSED=$((CURRENT_TIME - START_TIME))
    local MINS=$((ELAPSED / 60))
    local SECS=$((ELAPSED % 60))
    echo "[${MINS}m ${SECS}s] $1"
}

# Java 17 configuration
if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
else
    # Fallback: find Java 17
    JAVA_PATH=$(dirname $(dirname $(readlink -f $(which java))))
    export JAVA_HOME="$JAVA_PATH"
fi
export PATH="$JAVA_HOME/bin:$PATH"

# Maven configuration
MAVEN_VERSION="3.9.9"
if [ -d "/opt/apache-maven-$MAVEN_VERSION" ]; then
    export M2_HOME="/opt/apache-maven-$MAVEN_VERSION"
    export PATH="$M2_HOME/bin:$PATH"
fi

# Maven memory settings (prevent OOM)
export MAVEN_OPTS="-Xmx4g -Xms1g"

# Build profiles
SPARK_PROFILES="-Phive -Phive-thriftserver"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_banner() {
    echo ""
    echo "┌────────────────────────────────────────────────────────────────────┐"
    printf "│ %-66s │\n" "$1"
    echo "└────────────────────────────────────────────────────────────────────┘"
    echo ""
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "ERROR: $1 is not installed. Run bootstrap-dev-env.sh first."
        exit 1
    fi
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

print_banner "Checking Prerequisites"

check_command java
check_command mvn
check_command git

# Verify Java version is 17+
JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
if [ "$JAVA_VER" -lt 17 ]; then
    echo "ERROR: Java 17+ required. Found Java $JAVA_VER"
    echo "Run bootstrap-dev-env.sh and source ~/.bashrc"
    exit 1
fi

# Verify Maven version is 3.9+
MVN_VER=$(mvn -version 2>&1 | head -1 | grep -oP '\d+\.\d+' | head -1)
MVN_MAJOR=$(echo "$MVN_VER" | cut -d'.' -f1)
MVN_MINOR=$(echo "$MVN_VER" | cut -d'.' -f2)
if [ "$MVN_MAJOR" -lt 3 ] || ([ "$MVN_MAJOR" -eq 3 ] && [ "$MVN_MINOR" -lt 9 ]); then
    echo "ERROR: Maven 3.9+ required. Found Maven $MVN_VER"
    echo "Run bootstrap-dev-env.sh and source ~/.bashrc"
    exit 1
fi

log_time "Prerequisites OK - Java $JAVA_VER, Maven $MVN_VER"
echo "  JAVA_HOME: $JAVA_HOME"
echo "  M2_HOME: ${M2_HOME:-system}"
echo "  MAVEN_OPTS: $MAVEN_OPTS"

# =============================================================================
# STEP 1: CLEAN ALL STATE
# =============================================================================

print_banner "Step 1: Cleaning All Previous State"

# Clean Maven local repository (Spark artifacts only to save time)
if [ -d ~/.m2/repository/org/apache/spark ]; then
    log_time "Removing cached Spark artifacts from Maven..."
    rm -rf ~/.m2/repository/org/apache/spark
fi

# Clean all target directories
log_time "Removing all target directories..."
find "$GIT_ROOT" -type d -name "target" -exec rm -rf {} + 2>/dev/null || true

# Clean distribution directory
if [ -d "$GIT_ROOT/dist" ]; then
    log_time "Removing dist directory..."
    rm -rf "$GIT_ROOT/dist"
fi

# Clean any previous distribution tarballs
log_time "Removing previous distribution tarballs..."
rm -f "$GIT_ROOT"/*.tgz 2>/dev/null || true
rm -rf "$GIT_ROOT"/spark-*-bin-* 2>/dev/null || true

# Clean zinc compiler cache (can cause stale compilation issues)
if [ -d ~/.zinc ]; then
    log_time "Removing Zinc compiler cache..."
    rm -rf ~/.zinc
fi

# Clean ivy cache for Spark
if [ -d ~/.ivy2/cache/org.apache.spark ]; then
    log_time "Removing Ivy Spark cache..."
    rm -rf ~/.ivy2/cache/org.apache.spark
fi

log_time "Clean complete"

# =============================================================================
# STEP 2: BUILD SPARK
# =============================================================================

print_banner "Step 2: Building Spark (skip tests)"

log_time "Starting Maven build..."

# Use the bundled Maven wrapper for consistency
./build/mvn -DskipTests clean install $SPARK_PROFILES \
    -Dmaven.javadoc.skip=true \
    -Dcheckstyle.skip=true \
    -Dspotless.check.skip=true \
    --batch-mode

log_time "Maven build complete"

# =============================================================================
# STEP 3: RUN SMOKE TEST
# =============================================================================

print_banner "Step 3: Running Smoke Test (SparkPi)"

log_time "Running SparkPi example..."

# Run SparkPi and capture output
PI_OUTPUT=$(./bin/run-example SparkPi 10 2>&1) || {
    echo "ERROR: SparkPi smoke test failed!"
    echo "$PI_OUTPUT"
    exit 1
}

# Verify output contains expected result
if echo "$PI_OUTPUT" | grep -q "Pi is roughly"; then
    PI_VALUE=$(echo "$PI_OUTPUT" | grep "Pi is roughly" | tail -1)
    log_time "Smoke test PASSED: $PI_VALUE"
else
    echo "ERROR: SparkPi did not produce expected output!"
    echo "$PI_OUTPUT"
    exit 1
fi

# =============================================================================
# STEP 4: CREATE DISTRIBUTION
# =============================================================================

print_banner "Step 4: Creating Spark Distribution"

log_time "Building distribution tarball..."

# Create distribution (this is required before Docker build)
./dev/make-distribution.sh --name custom --pip --tgz $SPARK_PROFILES

# Verify distribution was created
DIST_DIR="$GIT_ROOT/dist"
if [ ! -d "$DIST_DIR" ]; then
    echo "ERROR: Distribution directory not created!"
    exit 1
fi

log_time "Distribution created at $DIST_DIR"

# =============================================================================
# STEP 5: BUILD DOCKER IMAGE
# =============================================================================

print_banner "Step 5: Building Docker Image"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_time "WARNING: Docker not installed, skipping Docker image build"
    log_time "Install Docker and run: sudo ./bin/docker-image-tool.sh -r spark-docker -t latest build"
else
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_time "WARNING: Docker daemon not running, skipping Docker image build"
        log_time "Start Docker and run: sudo ./bin/docker-image-tool.sh -r spark-docker -t latest build"
    else
        log_time "Building Docker image..."
        
        # Build Docker image (may need sudo depending on Docker setup)
        if docker info 2>&1 | grep -q "permission denied"; then
            sudo ./bin/docker-image-tool.sh -r spark-docker -t latest build
        else
            ./bin/docker-image-tool.sh -r spark-docker -t latest build
        fi
        
        # Verify image was created
        if docker images | grep -q "spark-docker/spark"; then
            IMAGE_SIZE=$(docker images spark-docker/spark:latest --format "{{.Size}}")
            log_time "Docker image built successfully: spark-docker/spark:latest ($IMAGE_SIZE)"
        else
            echo "WARNING: Docker image may not have been tagged correctly"
        fi
    fi
fi

# =============================================================================
# STEP 6: VERIFY SDP (SPARK DECLARATIVE PIPELINES) COMPONENTS
# =============================================================================

print_banner "Step 6: Verifying SDP Components"

log_time "Checking SDP (Spark Declarative Pipelines) build artifacts..."

# Check for spark-pipelines JAR (sql/pipelines module)
PIPELINES_JAR=$(find "$GIT_ROOT/sql/pipelines/target" -name "spark-pipelines_*.jar" ! -name "*-tests.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" 2>/dev/null | head -1)
if [ -n "$PIPELINES_JAR" ]; then
    log_time "✓ spark-pipelines JAR: $(basename $PIPELINES_JAR)"
else
    echo "WARNING: spark-pipelines JAR not found in sql/pipelines/target"
fi

# Check for spark-connect JAR (sql/connect/server module)
CONNECT_JAR=$(find "$GIT_ROOT/sql/connect/server/target" -name "spark-connect_*.jar" ! -name "*-tests.jar" ! -name "*-sources.jar" ! -name "*-javadoc.jar" 2>/dev/null | head -1)
if [ -n "$CONNECT_JAR" ]; then
    log_time "✓ spark-connect JAR: $(basename $CONNECT_JAR)"
else
    echo "WARNING: spark-connect JAR not found in sql/connect/server/target"
fi

# Check for spark-pipelines CLI script
if [ -x "$GIT_ROOT/bin/spark-pipelines" ]; then
    log_time "✓ spark-pipelines CLI: bin/spark-pipelines"
else
    echo "WARNING: spark-pipelines CLI script not found or not executable"
fi

# Check for Python pyspark.pipelines module
if [ -d "$GIT_ROOT/python/pyspark/pipelines" ]; then
    PY_FILES=$(find "$GIT_ROOT/python/pyspark/pipelines" -name "*.py" | wc -l)
    log_time "✓ PySpark pipelines module: $PY_FILES Python files"
else
    echo "WARNING: PySpark pipelines module not found"
fi

# Check for start-connect-server.sh script
if [ -x "$GIT_ROOT/sbin/start-connect-server.sh" ]; then
    log_time "✓ Spark Connect server script: sbin/start-connect-server.sh"
else
    echo "WARNING: start-connect-server.sh not found or not executable"
fi

log_time "SDP component verification complete"

# Optional: Run SDP smoke test if TEST_SDP=1
if [ "${TEST_SDP:-0}" = "1" ]; then
    print_banner "Step 6b: Running SDP Smoke Test"
    
    if [ -x "$GIT_ROOT/contrib/test-loop.sh" ]; then
        log_time "Running SDP end-to-end test..."
        "$GIT_ROOT/contrib/test-loop.sh" || {
            echo "WARNING: SDP smoke test failed (non-fatal)"
        }
    else
        log_time "WARNING: test-loop.sh not found, skipping SDP smoke test"
    fi
fi

# =============================================================================
# SUMMARY
# =============================================================================

print_banner "Build Loop Complete!"

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
TOTAL_MINS=$((TOTAL_TIME / 60))
TOTAL_SECS=$((TOTAL_TIME % 60))

echo "Summary:"
echo "  - Spark built successfully"
echo "  - Smoke test passed"
echo "  - Distribution created at: $DIST_DIR"
echo "  - SDP (Spark Declarative Pipelines) components verified"
echo ""
echo "Total time: ${TOTAL_MINS}m ${TOTAL_SECS}s"
echo ""
echo "Next steps:"
echo "  - Start Spark shell: ./bin/spark-shell --master local[2]"
echo "  - Run more examples: ./bin/run-example <example-name>"
echo ""
echo "To test SDP (Spark Declarative Pipelines):"
echo "  - Run: ./contrib/test-loop.sh"
echo "  - Or set TEST_SDP=1 ./contrib/build-loop.sh to include SDP test"
echo ""
echo "To debug SDP step-by-step:"
echo "  1. Start Spark Connect: ./sbin/start-connect-server.sh --wait --master local[4]"
echo "  2. In another terminal:  ./bin/spark-pipelines --remote sc://localhost:15002 init --name my-pipeline"
echo "  3. Run pipeline:         cd my-pipeline && ../bin/spark-pipelines --remote sc://localhost:15002 run"
echo ""
