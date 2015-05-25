
module Orchestrator
    class Trigger < Couchbase::Model
        design_document :trigger
        include ::CouchbaseId::Generator

        attribute :name
        attribute :description
        attribute :created_at,  default: lambda { Time.now.to_i }

        attribute :conditions
        attribute :actions,  default: lambda { [] }

        # in seconds
        attribute :debounce_period, default: 0


        protected


        before_delete   :cleanup_instances
        def cleanup_instances
            TriggerInstance.of(self.id).each do |trig|
                trig.delete
            end
        end

        # -----------
        # VALIDATIONS
        # -----------
        validates :name,       presence: true
        validates :conditions, presence: true
    end
end
