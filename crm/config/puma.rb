port ENV.fetch("PORT", 3000)
workers ENV.fetch("WEB_CONCURRENCY", 2)
threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
threads threads_count, threads_count
preload_app!
plugin :tmp_restart
