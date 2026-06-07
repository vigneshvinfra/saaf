# Observability — CloudWatch alarms for the AWS-managed dependencies Terraform
# owns (RDS, DynamoDB), an alerts SNS topic, and a summary dashboard.
#
# App-level SLOs (p95 end-to-end latency, 5xx rate, LLM error/timeout rate) are
# emitted by the agent via OpenTelemetry into Prometheus and alerted on with a
# PrometheusRule (deploy/platform/monitoring/) — that is where the runbook's
# "LLM latency spike" alert fires. CloudWatch covers the managed infra beneath.

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = "alias/aws/sns"
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == null ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ----- RDS alarms -----------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${var.name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU > 80% for 15m"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name          = "${var.name}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5 * 1024 * 1024 * 1024 # 5 GiB
  alarm_description   = "RDS free storage < 5 GiB"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "db_connections" {
  alarm_name          = "${var.name}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.db_connection_alarm_threshold
  alarm_description   = "RDS connections high — possible pool exhaustion"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# ----- DynamoDB alarms ------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ddb_throttle" {
  alarm_name          = "${var.name}-ddb-throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB idempotency table throttling"
  dimensions          = { TableName = var.dynamodb_table_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  tags                = var.tags
}

# ----- Dashboard ------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name}-infra"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title  = "RDS CPU / Connections",
          region = data.aws_region.current.name,
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id],
          ],
          period = 300, stat = "Average",
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title  = "DynamoDB capacity / throttles",
          region = data.aws_region.current.name,
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_table_name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.dynamodb_table_name],
            ["AWS/DynamoDB", "ThrottledRequests", "TableName", var.dynamodb_table_name],
          ],
          period = 300, stat = "Sum",
        }
      },
    ]
  })
}

data "aws_region" "current" {}
