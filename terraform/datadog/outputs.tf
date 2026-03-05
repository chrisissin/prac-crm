output "datadog_namespace" {
  description = "Kubernetes namespace for Datadog agent"
  value       = kubernetes_namespace.datadog.metadata[0].name
}

output "datadog_helm_release" {
  description = "Helm release name"
  value       = helm_release.datadog_agent.name
}
