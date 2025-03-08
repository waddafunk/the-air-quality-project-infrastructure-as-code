source ./get-data-lake-key.sh
source .env-airflow-runtime-variables

KV_NAME="airqualitykubedbkv${ENVIRONMENT}"

POSTGRES_HOST=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-postgres-host" --query value -o tsv 2>/dev/null || echo "air-quality-kube-airflow-pg-${ENV}.postgres.database.azure.com")
POSTGRES_USER=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-postgres-user" --query value -o tsv 2>/dev/null || echo "airflow_admin")
POSTGRES_PASSWORD=$(az keyvault secret show --vault-name "$KV_NAME" --name "airflow-postgres-password" --query value -o tsv)

# Delete configmap if it exists
kubectl delete configmap airflow-configmap --namespace=airflow --ignore-not-found=true

# Create the configmap
kubectl create configmap airflow-configmap \
  --from-literal=ENVIRONMENT=$ENVIRONMENT \
  --from-literal=LOG_LEVEL=info \
  --from-literal=ENERGY_DATA_URL=$ENERGY_DATA_URL \
  --from-literal=DATA_LAKE_RESOURCE_GROUP=$DATA_LAKE_RESOURCE_GROUP \
  --from-literal=PREFIX=$PREFIX \
  --namespace=airflow

# Delete secret if it exists
kubectl delete secret airflow-secrets --namespace=airflow --ignore-not-found=true

# Create the secret
kubectl create secret generic airflow-secrets \
  --from-literal=OPENAQ_API_KEY=$OPENAQ_API_KEY \
  --from-literal=EIA_API_KEY=$EIA_API \
  --from-literal=DATA_LAKE_KEY=$DATA_LAKE_KEY \
  --from-literal=POSTGRES_HOST=$POSTGRES_HOST \
  --from-literal=POSTGRES_USER=$POSTGRES_USER \
  --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  --from-literal=POSTGRES_PORT=$POSTGRES_PORT \
  --namespace=airflow