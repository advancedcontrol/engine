
module Orchestrator
    class Zone < Couchbase::Model
        design_document :zone
        include ::CouchbaseId::Generator


        before_delete :remove_zone


        attribute :name
        attribute :description
        attribute :settings,    default: lambda { {} }

        attribute :created_at,  default: lambda { Time.now.to_i }


        validates :name,  presence: true

        # Loads all the zones
        def self.all
            all(stale: false)
        end
        view :all


        protected


        def remove_zone
            ::Orchestrator::Control.instance.zones.delete(self.id)
            ::Orchestrator::ControlSystem.in_zone(self.id).each do |cs|
                cs.zones.delete(self.id)
                cs.save
            end
        end
    end
end
