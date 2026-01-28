#!/bin/bash
#
#
#       Sets up a dev env with all pre-reqs. This script is idempotent, it will
#       only attempt to install dependencies, if not exists.   
#
# ---------------------------------------------------------------------------------------
#

set -e
set -m

echo ""
echo "┌────────────────────────────────────┐"
echo "│ Checking for language dependencies │"
echo "└────────────────────────────────────┘"
echo ""

sudo apt update

# Spark 4.x requires Java 17 (minimum 17.0.11) and Maven 3.9+
JAVA_VERSION_REQUIRED=17

if java -version 2>&1 | grep -q "openjdk version \"17"; then
    echo "Java 17 already installed"
else
    echo "Installing JDK 17 (required for Spark 4.x)"
    sudo apt install -y openjdk-17-jdk
fi

# Find Java 17 installation path
JAVA17_PATH=$(dirname $(dirname $(readlink -f $(which java))))
if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
    JAVA17_PATH="/usr/lib/jvm/java-17-openjdk-amd64"
fi

if [ -z "$JAVA_HOME" ] || [[ "$JAVA_HOME" != *"17"* ]]; then
    echo "Setting JAVA_HOME to $JAVA17_PATH..."
    export JAVA_HOME=$JAVA17_PATH
    export PATH=$JAVA_HOME/bin:$PATH
    
    # Update .bashrc
    sed -i '/JAVA_HOME/d' ~/.bashrc 2>/dev/null || true
    echo "export JAVA_HOME=$JAVA17_PATH" >> ~/.bashrc
    echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
else
    echo "JAVA_HOME already set correctly to Java 17"
fi

# Install Maven 3.9+ (apt version may be too old)
MAVEN_VERSION="3.9.9"
if mvn -version 2>&1 | grep -q "Apache Maven 3\.9"; then
    echo "Maven 3.9+ already installed"
else
    echo "Installing Maven $MAVEN_VERSION (required for Spark 4.x)"
    
    # Download and install Maven manually for newer version
    if [ ! -d "/opt/apache-maven-$MAVEN_VERSION" ]; then
        wget -q https://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz -O /tmp/maven.tar.gz
        sudo tar -xzf /tmp/maven.tar.gz -C /opt/
        rm /tmp/maven.tar.gz
    fi
    
    # Set up Maven in PATH
    export M2_HOME=/opt/apache-maven-$MAVEN_VERSION
    export PATH=$M2_HOME/bin:$PATH
    
    # Update .bashrc
    sed -i '/M2_HOME/d' ~/.bashrc 2>/dev/null || true
    echo "export M2_HOME=/opt/apache-maven-$MAVEN_VERSION" >> ~/.bashrc
    echo 'export PATH=$M2_HOME/bin:$PATH' >> ~/.bashrc
fi

if [ ! -d ~/.m2/repository ]; then
    echo "Creating Maven cache directory"
    mkdir -p ~/.m2/repository
else
    echo "Maven cache directory already exists"
fi

echo ""
echo "┌───────────────────────────────┐"
echo "│ Installing VS Code extensions │"
echo "└───────────────────────────────┘"
echo ""

code --install-extension scalameta.metals@1.42.0
code --install-extension scala-lang.scala@0.5.8
code --install-extension vscjava.vscode-java-pack@0.29.0

echo ""
echo "┌──────────┐"
echo "│ Versions │"
echo "└──────────┘"
echo ""

echo "Java: $(java -version)"
echo "Maven: $(mvn -version)"