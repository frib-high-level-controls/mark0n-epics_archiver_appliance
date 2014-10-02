require 'puppet-lint/tasks/puppet-lint'

# work around an issue described here: https://github.com/rodjek/puppet-lint/issues/331
Rake::Task[:lint].clear

PuppetLint::RakeTask.new :lint do |config|
  # configure log format for Jenkins Warnings plug-in
  config.log_format = '%{path}:%{linenumber}:%{check}:%{KIND}:%{message}'
  config.disable_checks = [ "80chars" ]
  config.ignore_paths = ["modules/**/*.pp"]
end