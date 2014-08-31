
module Orchestrator
    module Api
        class ZonesController < ApiController
            respond_to :json
            before_action :check_admin
            before_action :find_zone, only: [:show, :update, :destroy]


            @@elastic ||= Elastic.new(Zone)


            def index
                query = @@elastic.query(params)
                query.sort = [{name: "asc"}]

                respond_with @@elastic.search(query)
            end

            def show
                respond_with @zone
            end

            def update
                @zone.update_attributes(safe_params)
                save_and_respond @zone do
                    # Update self in zone cache
                    expire_cache(@zone)
                end
            end

            def create
                zone = Zone.new(safe_params)
                save_and_respond zone do
                    # Add self to zone cache
                    expire_cache(zone)
                end
            end

            def destroy
                # delete will update CS and zone caches
                @zone.delete
                render :nothing => true
            end


            protected


            ZONE_PARAMS = [
                :name, :description,
                {groups: []}
            ]
            def safe_params
                settings = params[:settings]
                {
                    settings: settings.is_a?(::Hash) ? settings : {},
                    groups: []
                }.merge(params.permit(ZONE_PARAMS))
            end

            def find_zone
                # Find will raise a 404 (not found) if there is an error
                @zone = Zone.find(id)
            end

            def expire_cache(zone)
                ::Orchestrator::Control.instance.zones[zone.id] = zone
                ::Orchestrator::ControlSystem.in_zone(zone.id).each do |cs|
                    ::Orchestrator::System.expire(cs.id)
                end
            end
        end
    end
end
