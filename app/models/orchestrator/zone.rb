
module Orchestrator
    class Zone < Couchbase::Model
        design_document :zone
        include ::CouchbaseId::Generator


        before_delete :remove_zone


        attribute :name
        attribute :description
        attribute :settings,    default: lambda { {} }
        attribute :groups,      default: lambda { [] }

        attribute :created_at,  default: lambda { Time.now.to_i }


        validates :name,  presence: true


        def self.in_group(group_id)
            by_groups({key: group_id, stale: false})
        end
        view :by_groups


        protected


        def remove_zone
            ControlSystem.in_zone(self.id).each do |cs|
                cs.zones.delete(self.id)
                cs.save
            end
        end
    end
end
