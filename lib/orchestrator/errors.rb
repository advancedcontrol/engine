module Orchestrator
    class Error < StandardError

        # Called from:
        # * request_proxy
        # * requests_proxy
        class ProtectedMethod < Error; end
        class ModuleUnavailable < Error; end

        # Called from:
        # * dependency_manager
        class FileNotFound < Error; end

        # Called from:
        # * control
        class ModuleNotFound < Error; end

        # Called from:
        # * Device -> Processor
        class CommandFailure < Error; end
        class CommandCanceled < Error; end
    end
end
