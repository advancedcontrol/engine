
module Orchestrator
    module Api
        class ZonesController < ApiController
            respond_to :json
            #doorkeeper_for :all
            before_action :check_authorization, only: [:show, :update, :destroy]


            @@elastic ||= Elastic.new('zone')


            def index
                query = @@elastic.query(params)
                results = @@elastic.search(query)

                # Find by id doesn't raise errors
                respond_with Zone.find_by_id(results) || results
            end

            def show
                respond_with @zone
            end

            def update
                @zone.update_attributes(safe_params)
                save_and_respond @zone
            end

            def create
                zone = Zone.new(safe_params)
                save_and_respond zone
            end

            def destroy
                @zone.delete
                render :nothing => true
            end


            protected


            def safe_params
                params.require(:zone).permit(
                    :name, :description,
                    {settings: []}, {groups: []}
                )
            end

            def check_authorization
                # Find will raise a 404 (not found) if there is an error
                @zone = Zone.find(id)

                # Does the current user have permission to perform the current action?
            end
        end
    end
end
