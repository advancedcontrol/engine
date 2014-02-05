
module Orchestrator
    module Api
        class TrustsController < ApiController
            doorkeeper_for :all, :except => :show

            # List current trusts for the user
            def index
                render text: 'Hello Auth!'
            end

            # Used to trust the current device
            def create

            end

            # Destroy a trust
            def destroy

            end


            # This is used to build a new session
            def show

            end


            protected


            def check_user
                # TODO:: ensure user is
            end
        end
    end
end
