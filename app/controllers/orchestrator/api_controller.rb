
module Orchestrator
    class ApiController < ::Orchestrator::Base
    	

        protected


        # Access to the control system controller
        def control
            @@__control__ ||= ::Orchestrator::Control.instance
        end
    end
end
