
module Orchestrator
    module Api
        class TriggersController < ApiController
            respond_to :json
            
            # state, funcs, count and types are available to authenticated users
            before_action :check_admin,   only: [:create, :update, :destroy]
            before_action :check_support, only: [:index, :show]
            before_action :find_trigger,  only: [:show, :update, :destroy]


            @@elastic ||= Elastic.new(Trigger)


            def index
                query = @@elastic.query(params)
                query.sort = NAME_SORT_ASC
                respond_with @@elastic.search(query)
            end

            def show
                respond_with @trig
            end

            def update
                @trig.assign_attributes(safe_params)
                save_and_respond(@trig)
            end

            def create
                trig = Trigger.new(safe_params)
                save_and_respond trig
            end

            def destroy
                @trig.delete # expires the cache in after callback
                head :ok
            end


            protected


            # Better performance as don't need to create the object each time
            TRIGGER_PARAMS = [
                :name, :description, :debounce_period, :conditions, :actions
            ]
            # We need to support an arbitrary settings hash so have to
            # work around safe params as per 
            # http://guides.rubyonrails.org/action_controller_overview.html#outside-the-scope-of-strong-parameters
            def safe_params
                safe = params.permit(TRIGGER_PARAMS)
                resp = {}.merge(safe)
                cond = safe[:conditions]
                act = safe[:actions]

                if cond.class == String
                    cond = JSON.parse cond
                    if cond.is_a?(::Array)
                        resp[:conditions] = cond
                    end
                end

                if act.class == String
                    act = JSON.parse act
                    if act.is_a?(::Array)
                        resp[:actions] = act
                    end
                end

                resp
            end

            def find_trigger
                # Find will raise a 404 (not found) if there is an error
                @trig = Trigger.find(id)
            end
        end
    end
end
