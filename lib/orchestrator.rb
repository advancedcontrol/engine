require 'orchestrator/engine'


# Gems
require 'couchbase'
require 'couchbase-model'
require 'couchbase-id'


# System Core
require 'orchestrator/dependency_manager'   # Manages code loading
require 'orchestrator/control'              # Module control and system loader
require 'orchestrator/request'              # request wrapper (for user requests)
require 'orchestrator/version'              # orchestrator version
require 'orchestrator/system'               # This is the source of truth for all system information

# Common Abstractions
require 'orchestrator/core/module_manager'  # Base class of logic, device and service managers
require 'orchestrator/core/schedule_proxy'  # Common proxy for all module schedules
require 'orchestrator/core/requests_proxy'  # Sends a command to all modules of that type
require 'orchestrator/core/request_proxy'   # Sends a command to a single module
require 'orchestrator/core/system_proxy'    # prevents stale system objects
require 'orchestrator/core/scheduler'       # Common mixin function for modules classes

# Logic abstractions
require 'orchestrator/logic/manager'        # control system manager for logic modules
require 'orchestrator/logic/mixin'          # helper functions for logic module classes


# Optional utility modules
require 'orchestrator/utilities/transcoder' # functions for data manipulation
require 'orchestrator/utilities/constants'  # constants for readable code


module Orchestrator
end
