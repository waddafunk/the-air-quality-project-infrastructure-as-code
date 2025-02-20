# modules/aks-base/k8s-secrets.tf

# Provider for kubernetes
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

# Create a namespace for your ETL service if it doesn't exist
resource "kubernetes_namespace" "etl" {
  metadata {
    name = "etl"
    
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

# Create service account for workload identity
resource "kubernetes_service_account" "etl" {
  metadata {
    name      = "etl-service-account"
    namespace = kubernetes_namespace.etl.metadata[0].name
    annotations = {
      "azure.workload.identity/client-id" = azurerm_kubernetes_cluster.aks.kubelet_identity[0].client_id
    }
  }
}
