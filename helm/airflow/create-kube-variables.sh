source ./get-data-lake-key.sh
source .env-airflow-runtime-variables

kubectl create configmap airflow-configmap \
  --from-literal=ENVIRONMENT=$ENVIRONMENT \
  --from-literal=LOG_LEVEL=info \
  --from-literal=ENERGY_DATA_URL=$ENERGY_DATA_URL \
  --from-literal=DATA_LAKE_RESOURCE_GROUP=$DATA_LAKE_RESOURCE_GROUP \
  --from-literal=PREFIX=$PREFIX \
  --namespace=airflow \
  || echo "Configmap already exists"

kubectl create secret generic airflow-secrets \
  --from-literal=OPENAQ_API_KEY=$OPENAQ_API_KEY \
  --from-literal=EIA_API_KEY=$EIA_API \
  --from-literal=DATA_LAKE_KEY=$DATA_LAKE_KEY \
  --namespace=airflow \
  || echo "Secrets already exist"