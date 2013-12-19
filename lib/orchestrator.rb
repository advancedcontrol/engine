require 'orchestrator/engine'


# Gems
require 'couchbase'
require 'couchbase-model'
require 'couchbase-id'


# System Core
require 'orchestrator/dependency_manager'
require 'orchestrator/module_manager'
require 'orchestrator/connection'
require 'orchestrator/request'
require 'orchestrator/version'
require 'orchestrator/system'


# Module abstractions
require 'orchestrator/logic/schedule_proxy' # proxy for scheduling so we have oversight
require 'orchestrator/logic/scheduler'      # auto included in logic modules
require 'orchestrator/logic/manager'        # control system manager for logic modules


# Optional utility modules
require 'orchestrator/utilities/transcoder' # functions for data manipulation
require 'orchestrator/utilities/constants'  # constants for readable code


module Orchestrator
end
