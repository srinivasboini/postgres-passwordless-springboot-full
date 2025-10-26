#!/bin/bash
# Usage: ./deploy_app.sh <RG> <APP_NAME>
RG=$1
APP_NAME=$2

mvn -DskipTests package

JAR=$(ls target/*.jar | head -n1)
if [ -z "$JAR" ]; then
  echo "Jar not found. Build failed?"
  exit 1
fi

echo "Deploying $JAR to $APP_NAME"
az webapp deploy --resource-group $RG --name $APP_NAME --type jar --src-path "$JAR"
