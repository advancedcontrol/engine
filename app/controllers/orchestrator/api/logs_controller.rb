
module Orchestrator
    module Api
        class LogsController < ApiController
            respond_to :json
            before_action :doorkeeper_authorize!
            before_action :check_admin


            # deal with live reload   filter
            @@elastic ||= Elastic.new(::Orchestrator::AccessLog)


            UserId = 'doc.user_id'.freeze
            def index
                query = @@elastic.query(params)

                # Filter systems via user_id
                if params.has_key? :user_id
                    user_id = params.permit(:user_id)[:user_id]
                    query.filter({
                        UserId => [user_id]
                    })
                end

                results = @@elastic.search(query) do |entry|
                    entry.as_json.tap do |json|
                        json[:systems] = ControlSystem.find_by_id(json[:systems]).as_json(only: [:id, :name]) || []
                    end
                end
                respond_with results
            end
        end
    end
end
