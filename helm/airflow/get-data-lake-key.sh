source .env-airflow-runtime-variables

KEY=$(az storage account keys list --account-name "airqualitykubedls${ENVIRONMENT}" --query "[0].value" -o tsv)
ESCAPED_VALUE=$(printf '%s\n' "$KEY" | sed -e 's/[\/&]/\\&/g')

sed -i "s/DATA_LAKE_KEY=.*/DATA_LAKE_KEY=$ESCAPED_VALUE/" .env-airflow-runtime-variables