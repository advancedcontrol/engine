
module Orchestrator
    class ApiController < ::AcaEngineBase

        protected


        # Access to the control system controller
        def control
            @@__control__ ||= ::Orchestrator::Control.instance
        end
    end
end
