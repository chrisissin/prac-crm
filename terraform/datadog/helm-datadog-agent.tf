# Datadog Agent Helm chart on EKS with MySQL DBM Cluster Check

locals {
  mysql_cluster_check_config = yamlencode({
    cluster_check = true
    init_config   = {}
    instances = concat(
      [
        {
          dbm       = true
          host      = var.mysql_master_host
          port      = 3306
          username  = "datadog"
          password  = var.mysql_datadog_password
          tags      = ["role:master", "env:${var.environment}"]
          reported_hostname = "mysql-master"
        }
      ],
      [
        for i, h in var.mysql_replica_hosts : {
          dbm       = true
          host      = h
          port      = 3306
          username  = "datadog"
          password  = var.mysql_datadog_password
          tags      = ["role:replica", "env:${var.environment}", "replica:${i + 1}"]
          options   = { replication = true }
          reported_hostname = "mysql-replica-${i + 1}"
        }
      ]
    )
  })
}

resource "kubernetes_namespace" "datadog" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_secret" "datadog" {
  metadata {
    name      = "datadog-agent"
    namespace = kubernetes_namespace.datadog.metadata[0].name
  }

  data = {
    api-key = var.datadog_api_key
    app-key = var.datadog_app_key
  }
}

resource "helm_release" "datadog_agent" {
  name       = "datadog-agent"
  repository = "https://helm.datadoghq.com"
  chart      = "datadog"
  namespace  = kubernetes_namespace.datadog.metadata[0].name
  version    = "4.12.6"

  values = [
    yamlencode({
      targetSystem = "linux"

      datadog = {
        apiKeyExistingSecret = kubernetes_secret.datadog.metadata[0].name
        appKeyExistingSecret = kubernetes_secret.datadog.metadata[0].name
        site                 = var.datadog_site
        clusterName          = var.cluster_name
        tags                 = ["env:${var.environment}", "project:crm"]
        processAgent = { enabled = true }
        systemProbe  = { enabled = true }
        logs         = { enabled = true }
        apm          = { socketEnabled = true }
      }

      clusterChecks = { enabled = true }

      agents = {
        tolerations = [
          {
            key      = "node-role.kubernetes.io/master"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]
      }

      clusterAgent = {
        enabled  = true
        replicas = 1
        confd = {
          "mysql.yaml" = local.mysql_cluster_check_config
        }
      }
    })
  ]
}
