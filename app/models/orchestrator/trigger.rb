
module Orchestrator
    class Trigger < Couchbase::Model
        design_document :trigger
        include ::CouchbaseId::Generator

        attribute :name
        attribute :description
        attribute :created_at,  default: lambda { Time.now.to_i }

        attribute :conditions,  default: lambda { [] }
        attribute :actions,  default: lambda { [] }


        # Returns a list of triggers for the system provided
        def for(sys_id)

        end


        protected


        # Validate that
        # * there are some conditions entered
        # * there are some actions entered
    end
end
