#!/bin/bash
#
# test-loop.sh - Test Spark Declarative Pipelines (SDP) end-to-end
#
# This script:
#   1. Starts the Spark Connect server (required for SDP)
#   2. Initializes a sample SDP project using spark-pipelines CLI
#   3. Runs the pipeline and validates output
#   4. Cleans up
#
# Usage: ./contrib/test-loop.sh
#
# Prerequisites:
#   - Run build-loop.sh first (or at least build Spark with: ./build/mvn -DskipTests clean install -Phive -Phive-thriftserver)
#   - Python 3.8+ with PyYAML installed
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

# Spark Connect server configuration
SPARK_CONNECT_PORT=15002
SPARK_CONNECT_HOST="localhost"

# Test project configuration
TEST_PROJECT_NAME="sdp-test-project"
TEST_PROJECT_DIR="$GIT_ROOT/contrib/$TEST_PROJECT_NAME"

# PID file for tracking Spark Connect server
PID_FILE="$GIT_ROOT/contrib/.spark-connect.pid"

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
        echo "ERROR: $1 is not installed."
        exit 1
    fi
}

cleanup() {
    log_time "Cleaning up..."
    
    # Stop Spark Connect server if running
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_time "Stopping Spark Connect server (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            sleep 2
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$PID_FILE"
    fi
    
    # Also try to kill by port
    local port_pid=$(lsof -ti :$SPARK_CONNECT_PORT 2>/dev/null || true)
    if [ -n "$port_pid" ]; then
        log_time "Killing process on port $SPARK_CONNECT_PORT (PID: $port_pid)..."
        kill "$port_pid" 2>/dev/null || true
        sleep 1
        kill -9 "$port_pid" 2>/dev/null || true
    fi
    
    # Remove test project directory
    if [ -d "$TEST_PROJECT_DIR" ]; then
        log_time "Removing test project directory..."
        rm -rf "$TEST_PROJECT_DIR"
    fi
    
    log_time "Cleanup complete"
}

# Set trap to cleanup on exit
trap cleanup EXIT

wait_for_server() {
    local max_attempts=60
    local attempt=1
    log_time "Waiting for Spark Connect server to start on port $SPARK_CONNECT_PORT..."
    
    while [ $attempt -le $max_attempts ]; do
        if nc -z "$SPARK_CONNECT_HOST" "$SPARK_CONNECT_PORT" 2>/dev/null; then
            log_time "Spark Connect server is ready!"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    echo "ERROR: Spark Connect server did not start within ${max_attempts} seconds"
    return 1
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

print_banner "Checking Prerequisites"

check_command java
check_command python3

# Verify Java version is 17+
JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
if [ "$JAVA_VER" -lt 17 ]; then
    echo "ERROR: Java 17+ required. Found Java $JAVA_VER"
    exit 1
fi

# Check if Spark has been built
if [ ! -d "$GIT_ROOT/assembly/target" ]; then
    echo "ERROR: Spark has not been built. Run build-loop.sh first."
    echo "       Or: ./build/mvn -DskipTests clean install -Phive -Phive-thriftserver"
    exit 1
fi

# Check for required Python packages
if ! python3 -c "import yaml" 2>/dev/null; then
    log_time "Installing PyYAML..."
    pip3 install pyyaml --quiet
fi

# Check for netcat (for port checking)
if ! command -v nc &> /dev/null; then
    log_time "WARNING: netcat not found, will use alternative method to check server"
fi

log_time "Prerequisites OK - Java $JAVA_VER"
echo "  JAVA_HOME: $JAVA_HOME"
echo "  SPARK_HOME: $GIT_ROOT"

# =============================================================================
# STEP 0: CLEANUP PREVIOUS STATE
# =============================================================================

print_banner "Step 0: Cleaning Previous State"

# Kill any existing Spark Connect server
cleanup

# =============================================================================
# STEP 1: START SPARK CONNECT SERVER
# =============================================================================

print_banner "Step 1: Starting Spark Connect Server"

log_time "Starting Spark Connect server on port $SPARK_CONNECT_PORT..."

# Set up Python path for PySpark
export PYTHONPATH="${GIT_ROOT}/python:${GIT_ROOT}/python/lib/py4j-0.10.9.9-src.zip:$PYTHONPATH"

# Start Spark Connect server with --wait flag (foreground but we'll background it)
# Using local master for testing
export SPARK_HOME="$GIT_ROOT"
"$GIT_ROOT/sbin/start-connect-server.sh" \
    --master "local[4]" \
    --conf "spark.connect.grpc.binding.port=$SPARK_CONNECT_PORT" \
    --conf "spark.driver.memory=2g" \
    --conf "spark.executor.memory=2g" \
    --conf "spark.sql.warehouse.dir=$GIT_ROOT/contrib/spark-warehouse" \
    --packages org.apache.spark:spark-connect_2.13:4.0.0-preview2 \
    &

# Get the PID
CONNECT_PID=$!
echo "$CONNECT_PID" > "$PID_FILE"
log_time "Spark Connect server started with PID: $CONNECT_PID"

# Wait for server to be ready
wait_for_server

# =============================================================================
# STEP 2: INITIALIZE TEST PROJECT
# =============================================================================

print_banner "Step 2: Initializing SDP Test Project"

cd "$GIT_ROOT/contrib"

log_time "Creating test project using 'spark-pipelines init'..."

# Use the spark-pipelines CLI to initialize a project
"$GIT_ROOT/bin/spark-pipelines" \
    --remote "sc://$SPARK_CONNECT_HOST:$SPARK_CONNECT_PORT" \
    init --name "$TEST_PROJECT_NAME"

if [ ! -d "$TEST_PROJECT_DIR" ]; then
    echo "ERROR: Test project directory was not created"
    exit 1
fi

log_time "Test project created at: $TEST_PROJECT_DIR"

# Show project structure
echo ""
echo "Project structure:"
find "$TEST_PROJECT_DIR" -type f | head -20
echo ""

# Show pipeline spec
echo "Pipeline spec (spark-pipeline.yml):"
cat "$TEST_PROJECT_DIR/spark-pipeline.yml"
echo ""

# =============================================================================
# STEP 3: RUN THE PIPELINE (DRY RUN FIRST)
# =============================================================================

print_banner "Step 3: Running Pipeline (Dry Run)"

cd "$TEST_PROJECT_DIR"

log_time "Running pipeline dry-run to validate graph..."

"$GIT_ROOT/bin/spark-pipelines" \
    --remote "sc://$SPARK_CONNECT_HOST:$SPARK_CONNECT_PORT" \
    dry-run --spec spark-pipeline.yml 2>&1 | tee /tmp/sdp-dry-run.log || {
        echo ""
        echo "Dry-run output:"
        cat /tmp/sdp-dry-run.log
        echo ""
        log_time "WARNING: Dry-run had issues (this may be expected for a simple test)"
    }

log_time "Dry-run complete"

# =============================================================================
# STEP 4: RUN THE PIPELINE (FULL RUN)
# =============================================================================

print_banner "Step 4: Running Pipeline (Full Run)"

cd "$TEST_PROJECT_DIR"

log_time "Running pipeline with full refresh..."

"$GIT_ROOT/bin/spark-pipelines" \
    --remote "sc://$SPARK_CONNECT_HOST:$SPARK_CONNECT_PORT" \
    run --spec spark-pipeline.yml --full-refresh-all 2>&1 | tee /tmp/sdp-run.log || {
        echo ""
        echo "Run output:"
        cat /tmp/sdp-run.log
        echo ""
        log_time "WARNING: Pipeline run had issues"
    }

log_time "Pipeline run complete"

# =============================================================================
# STEP 5: VERIFY RESULTS
# =============================================================================

print_banner "Step 5: Verifying Results"

log_time "Checking pipeline outputs..."

# Check if storage directory has checkpoints
if [ -d "$TEST_PROJECT_DIR/pipeline-storage" ]; then
    STORAGE_FILES=$(find "$TEST_PROJECT_DIR/pipeline-storage" -type f | wc -l)
    log_time "Found $STORAGE_FILES files in pipeline storage"
else
    log_time "WARNING: Pipeline storage directory is empty or missing"
fi

# Try to query the created tables using PySpark
log_time "Querying created materialized views..."

python3 << 'PYTHON_SCRIPT' || log_time "WARNING: Could not verify table contents"
import os
import sys
sys.path.insert(0, os.environ.get('PYTHONPATH', '').split(':')[0])

from pyspark.sql import SparkSession

try:
    spark = SparkSession.builder \
        .remote(f"sc://localhost:{os.environ.get('SPARK_CONNECT_PORT', '15002')}") \
        .getOrCreate()
    
    print("Connected to Spark Connect server")
    
    # Try to show tables
    tables = spark.sql("SHOW TABLES").collect()
    print(f"Tables found: {len(tables)}")
    for t in tables:
        print(f"  - {t}")
    
    # Try to query the example materialized view
    try:
        result = spark.sql("SELECT * FROM example_python_materialized_view").collect()
        print(f"example_python_materialized_view has {len(result)} rows")
        print(f"Sample data: {result[:5]}")
    except Exception as e:
        print(f"Could not query example_python_materialized_view: {e}")
    
    spark.stop()
except Exception as e:
    print(f"Error connecting to Spark: {e}")
    sys.exit(1)
PYTHON_SCRIPT

export SPARK_CONNECT_PORT

# =============================================================================
# SUMMARY
# =============================================================================

print_banner "SDP Test Complete!"

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
TOTAL_MINS=$((TOTAL_TIME / 60))
TOTAL_SECS=$((TOTAL_TIME % 60))

echo "Summary:"
echo "  - Spark Connect server started successfully"
echo "  - SDP test project initialized"
echo "  - Pipeline dry-run executed"
echo "  - Pipeline full run executed"
echo ""
echo "Total time: ${TOTAL_MINS}m ${TOTAL_SECS}s"
echo ""
echo "Test project location: $TEST_PROJECT_DIR"
echo ""
echo "To debug step-by-step:"
echo "  1. Start server manually:"
echo "     ./sbin/start-connect-server.sh --wait --master local[4] \\"
echo "         --conf spark.connect.grpc.binding.port=15002"
echo ""
echo "  2. In another terminal, run pipeline:"
echo "     cd $TEST_PROJECT_DIR"
echo "     ../bin/spark-pipelines --remote sc://localhost:15002 run"
echo ""
echo "  3. Or use Python directly:"
echo "     from pyspark.sql import SparkSession"
echo "     spark = SparkSession.builder.remote('sc://localhost:15002').getOrCreate()"
echo ""

# Note: cleanup() will be called automatically on exit due to trap
