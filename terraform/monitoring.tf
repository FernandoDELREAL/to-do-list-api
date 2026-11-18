# ---------------------------------------------------------------------------
# Observabilidad: SNS + alarmas + dashboard
# Las alarmas y el dashboard se definen en ../alerting/*.json y Terraform
# solo los lee y sustituye el ID de la instancia y la region.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  alarms = jsondecode(file("${path.module}/../alerting/alarms.json"))
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = { for a in local.alarms : a.AlarmName => a }

  alarm_name          = each.value.AlarmName
  alarm_description   = each.value.AlarmDescription
  namespace           = each.value.Namespace
  metric_name         = each.value.MetricName
  statistic           = each.value.Statistic
  period              = each.value.Period
  evaluation_periods  = each.value.EvaluationPeriods
  datapoints_to_alarm = try(each.value.DatapointsToAlarm, null)
  threshold           = each.value.Threshold
  comparison_operator = each.value.ComparisonOperator
  treat_missing_data  = each.value.TreatMissingData

  dimensions = {
    for k, v in try(each.value.Dimensions, {}) :
    k => replace(v, "__INSTANCE_ID__", aws_instance.app.id)
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "todo" {
  dashboard_name = "${var.project_name}-dashboard"
  dashboard_body = replace(
    replace(file("${path.module}/../alerting/cloudwatch-dashboard.json"), "__INSTANCE_ID__", aws_instance.app.id),
    "__REGION__", var.aws_region
  )
}
