require 'orchestrator/engine'


# Gems
require 'couchbase'
require 'couchbase-model'
require 'couchbase-id'
require 'uv-rays'


# System Main
require 'orchestrator/dependency_manager'   # Manages code loading
require 'orchestrator/websocket_manager'    # Websocket interface
require 'orchestrator/control'              # Module control and system loader
require 'orchestrator/version'              # orchestrator version
require 'orchestrator/system'               # This is the source of truth for all system information
require 'orchestrator/status'               # Manages status subscriptions across threads
require 'orchestrator/logger'               # Logs events of interest as well as coordinating live log feedback
require 'orchestrator/errors'               # A list of errors that can occur within the system

# Core Abstractions
require 'orchestrator/core/module_manager'  # Base class of logic, device and service managers
require 'orchestrator/core/schedule_proxy'  # Common proxy for all module schedules
require 'orchestrator/core/requests_proxy'  # Sends a command to all modules of that type
require 'orchestrator/core/request_proxy'   # Sends a command to a single module
require 'orchestrator/core/system_proxy'    # prevents stale system objects (maintains loose coupling)
require 'orchestrator/core/mixin'           # Common mixin functions for modules classes

# Logic abstractions
require 'orchestrator/logic/manager'        # control system manager for logic modules
require 'orchestrator/logic/mixin'          # helper functions for logic module classes


# Optional utility modules
require 'orchestrator/utilities/transcoder' # functions for data manipulation
require 'orchestrator/utilities/constants'  # constants for readable code


module Orchestrator
end
