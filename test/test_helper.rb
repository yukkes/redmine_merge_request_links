# frozen_string_literal: true

# For unknown reasons, column information is not reloaded correctly
# when running the `db:migrate` and `redmine:plugins:test` tasks in
# one `rake` call. Reset manually.
ActiveRecord::Base.descendants.each(&:reset_column_information) if defined?(ActiveRecord)

# Suppress warnings
$VERBOSE = false

# Load the Redmine helper
require File.expand_path("#{File.dirname(__FILE__)}/../../../test/test_helper")

Rails.logger.level = :warn
