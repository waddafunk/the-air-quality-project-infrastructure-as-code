# Create namespace for Airflow
resource "kubernetes_namespace" "airflow" {
  metadata {
    name = var.namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

# Generate random passwords
resource "random_password" "postgres_password" {
  length  = 16
  special = false
}

resource "random_password" "admin_password" {
  length  = 16
  special = false
}

# Deploy PostgreSQL first
resource "helm_release" "postgresql" {
  name       = "airflow-postgresql"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  namespace  = kubernetes_namespace.airflow.metadata[0].name
  version    = "12.5.6"

  values = [
    yamlencode({
      auth = {
        username = "airflow"
        password = random_password.postgres_password.result
        database = "airflow"
      }
      primary = {
        persistence = {
          size = "10Gi"
        }
      }
    })
  ]
}

# Initialize Airflow database
resource "kubernetes_job" "airflow_init" {
  depends_on = [helm_release.postgresql]

  metadata {
    name      = "airflow-init"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }

  spec {
    template {
      metadata {
        name = "airflow-init"
      }

      spec {
        container {
          name    = "airflow-init"
          image   = "apache/airflow:2.7.1"
          command = ["/bin/bash", "-c"]
          args    = ["airflow db init && airflow users create --username admin --password ${random_password.admin_password.result} --firstname Admin --lastname User --role Admin --email admin@example.com"]

          env {
            name  = "AIRFLOW__CORE__SQL_ALCHEMY_CONN"
            value = "postgresql+psycopg2://airflow:${random_password.postgres_password.result}@airflow-postgresql:5432/airflow"
          }
        }
        restart_policy = "Never"
      }
    }
    backoff_limit = 4
  }
}

# Store passwords in Kubernetes secrets
resource "kubernetes_secret" "airflow_secrets" {
  metadata {
    name      = "airflow-secrets"
    namespace = kubernetes_namespace.airflow.metadata[0].name
  }

  data = {
    postgres_password = random_password.postgres_password.result
    admin_password    = random_password.admin_password.result
  }
}

# Deploy Airflow
resource "helm_release" "airflow" {
  depends_on = [
    helm_release.postgresql,
    kubernetes_job.airflow_init
  ]

  name       = "airflow"
  repository = "https://airflow.apache.org"
  chart      = "airflow"
  namespace  = kubernetes_namespace.airflow.metadata[0].name
  version    = "1.11.0"

  values = [
    yamlencode(merge({
      executor = "CeleryExecutor"
      postgresql = {
        enabled = false  # We're using our own PostgreSQL
      }
      data = {
        metadataConnection = {
          user     = "airflow"
          pass     = random_password.postgres_password.result
          host     = "airflow-postgresql"
          port     = 5432
          db       = "airflow"
          protocol = "postgresql"
        }
      }
      webserver = {
        service = {
          type = "ClusterIP"
        }
      }
      redis = {
        enabled = true
      }
      workers = {
        replicas = 3
      }
    }, var.airflow_values))
  ]
}

# Add RBAC for Airflow to access Data Lake
resource "azurerm_role_assignment" "airflow_storage_role" {
  scope                = data.azurerm_storage_account.datalake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_kubernetes_cluster.aks.identity[0].principal_id

  lifecycle {
    ignore_changes = [
      scope,
      principal_id,
    ]
  }
}

