# =============================================================================
# ChainLearn Monitoring Module
# CloudWatch, Grafana, Prometheus, Alarms
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# SNS Topic for Alerts
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"

  tags = {
    Name        = "${var.project_name}-${var.environment}-alerts"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_sns_topic_subscription" "email" {
  count     = length(var.alert_email_addresses)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email_addresses[count.index]
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarms"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Dashboards
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", "${var.project_name}-api", "ClusterName", "${var.project_name}-${var.environment}"],
            ["AWS/ECS", "CPUUtilization", "ServiceName", "${var.project_name}-frontend", "ClusterName", "${var.project_name}-${var.environment}"],
            ["AWS/ECS", "CPUUtilization", "ServiceName", "${var.project_name}-indexer", "ClusterName", "${var.project_name}-${var.environment}"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "ECS CPU Utilization"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ServiceName", "${var.project_name}-api", "ClusterName", "${var.project_name}-${var.environment}"],
            ["AWS/ECS", "MemoryUtilization", "ServiceName", "${var.project_name}-frontend", "ClusterName", "${var.project_name}-${var.environment}"],
            ["AWS/ECS", "MemoryUtilization", "ServiceName", "${var.project_name}-indexer", "ClusterName", "${var.project_name}-${var.environment}"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "ECS Memory Utilization"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${var.project_name}-${var.environment}"],
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", "${var.project_name}-${var.environment}"],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", "${var.project_name}-${var.environment}"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "RDS Metrics"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", "${var.project_name}-${var.environment}"],
            ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "CacheClusterId", "${var.project_name}-${var.environment}"],
            ["AWS/ElastiCache", "CurrConnections", "CacheClusterId", "${var.project_name}-${var.environment}"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Redis Metrics"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
          period = 60
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "ALB Request Metrics"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Metric Filters
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${var.project_name}-${var.environment}-error-count"
  pattern        = "ERROR"
  log_group_name = var.ecs_log_group_name

  metric_transformation {
    name          = "ErrorCount"
    namespace     = "${var.project_name}/${var.environment}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "api_5xx_count" {
  name           = "${var.project_name}-${var.environment}-api-5xx"
  pattern        = "[..., status=5*, ...]"
  log_group_name = var.ecs_log_group_name

  metric_transformation {
    name          = "API5xxCount"
    namespace     = "${var.project_name}/${var.environment}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "contract_event_count" {
  name           = "${var.project_name}-${var.environment}-contract-events"
  pattern        = "[..., event_type=\"contract_event\", ...]"
  log_group_name = var.ecs_log_group_name

  metric_transformation {
    name          = "ContractEventCount"
    namespace     = "${var.project_name}/${var.environment}"
    value         = "1"
    default_value = "0"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "API is returning 5xx errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "api_high_latency" {
  alarm_name          = "${var.project_name}-${var.environment}-api-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "p99"
  threshold           = 5
  alarm_description   = "API p99 latency is above 5 seconds"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_high_cpu" {
  for_each = toset(var.ecs_service_names)

  alarm_name          = "${var.project_name}-${var.environment}-${each.value}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "${each.value} service CPU is above 85%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = each.value
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Service     = each.value
  }
}

resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "${var.project_name}-${var.environment}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorCount"
  namespace           = "${var.project_name}/${var.environment}"
  period              = 300
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "Error log count is above 50 in 5 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Grafana Workspace (Amazon Managed Grafana)
# -----------------------------------------------------------------------------
resource "aws_grafana_workspace" "main" {
  name                     = "${var.project_name}-${var.environment}"
  description              = "ChainLearn Grafana workspace for ${var.environment}"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  data_sources             = ["CLOUDWATCH", "PROMETHEUS"]

  vpc_configuration {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.grafana_security_group_id]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-grafana"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_grafana_role_association" "admin" {
  role         = "ADMIN"
  user_ids     = var.grafana_admin_user_ids
  workspace_id = aws_grafana_workspace.main.id
}

# -----------------------------------------------------------------------------
# Prometheus Scraper (Amazon Managed Service for Prometheus)
# -----------------------------------------------------------------------------
resource "aws_prometheus_workspace" "main" {
  alias = "${var.project_name}-${var.environment}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-prometheus"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_prometheus_scraper" "main" {
  scrape_configuration = jsonencode({
    global = {
      scrape_interval = "30s"
    }
    scrape_configs = [
      {
        job_name     = "chainlearn-api"
        metrics_path = "/metrics"
        static_configs = [
          {
            targets = ["${var.project_name}-api.${var.project_name}.local:3001"]
          }
        ]
      },
      {
        job_name     = "chainlearn-ai"
        metrics_path = "/metrics"
        static_configs = [
          {
            targets = ["${var.project_name}-ai.${var.project_name}.local:8000"]
          }
        ]
      },
      {
        job_name     = "chainlearn-indexer"
        metrics_path = "/metrics"
        static_configs = [
          {
            targets = ["${var.project_name}-indexer.${var.project_name}.local:3002"]
          }
        ]
      }
    ]
  })

  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.main.arn
    }
  }

  role_arn = aws_iam_role.prometheus_scraper.arn

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role" "prometheus_scraper" {
  name = "${var.project_name}-${var.environment}-prometheus-scraper"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "aps.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "prometheus_scraper" {
  name = "${var.project_name}-${var.environment}-prometheus-scraper"
  role = aws_iam_role.prometheus_scraper.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = aws_prometheus_workspace.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:DescribeContainerInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_region" "current" {}
