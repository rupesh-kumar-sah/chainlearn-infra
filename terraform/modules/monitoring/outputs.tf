# =============================================================================
# ChainLearn Monitoring Module - Outputs
# =============================================================================

output "sns_alert_topic_arn" {
  description = "ARN of the SNS alert topic"
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "grafana_workspace_id" {
  description = "ID of the Grafana workspace"
  value       = aws_grafana_workspace.main.id
}

output "grafana_workspace_endpoint" {
  description = "Endpoint of the Grafana workspace"
  value       = aws_grafana_workspace.main.endpoint
}

output "grafana_workspace_url" {
  description = "URL of the Grafana workspace"
  value       = "https://${aws_grafana_workspace.main.endpoint}"
}

output "prometheus_workspace_id" {
  description = "ID of the Prometheus workspace"
  value       = aws_prometheus_workspace.main.id
}

output "prometheus_workspace_arn" {
  description = "ARN of the Prometheus workspace"
  value       = aws_prometheus_workspace.main.arn
}

output "prometheus_workspace_endpoint" {
  description = "Endpoint of the Prometheus workspace"
  value       = aws_prometheus_workspace.main.prometheus_endpoint
}

data "aws_region" "current" {}
