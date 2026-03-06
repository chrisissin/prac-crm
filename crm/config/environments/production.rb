require "active_support/core_ext/integer/time"
Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.enabled = true
  # Set to true when using an HTTPS-terminating LB (e.g. ALB with ACM cert)
  config.force_ssl = ENV.fetch("FORCE_SSL", "false") == "true"
  config.log_level = :info
  config.log_tags = [:request_id]
  # Log to stdout so kubectl logs shows errors (500s, exceptions)
  config.log_to_stdout = true
  config.active_support.deprecation = :notify
  config.i18n.fallbacks = true
end
