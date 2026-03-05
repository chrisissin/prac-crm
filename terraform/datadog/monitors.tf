# Optional: Datadog Monitors for MySQL
# Uncomment and customize as needed

# resource "datadog_monitor" "mysql_replication_lag" {
#   name    = "[CRM] MySQL Replication Lag"
#   type    = "metric alert"
#   message = "MySQL replica lag is high. Notify @pagerduty"
#
#   query = "avg(last_5m):avg:mysql.replication.seconds_behind_master{*} by {host} > 60"
#
#   monitor_thresholds {
#     critical = 60
#     warning  = 30
#   }
#
#   tags = ["env:${var.environment}", "service:mysql"]
# }
#
# resource "datadog_monitor" "mysql_connections" {
#   name    = "[CRM] MySQL Connection Usage High"
#   type    = "metric alert"
#   message = "MySQL connection usage is high"
#
#   query = "avg(last_5m):(avg:mysql.performance.threads_connected{*} by {host} / avg:mysql.performance.max_connections{*} by {host}) * 100 > 80"
#
#   monitor_thresholds {
#     critical = 90
#     warning  = 80
#   }
#
#   tags = ["env:${var.environment}", "service:mysql"]
# }
