
module Orchestrator
    class Group < Couchbase::Model
        design_document :grp
        include ::CouchbaseId::Generator


        CLEARANCE_LEVELS = ::Rails.configuration.orchestrator.clearance_levels


        # User groups
        attribute :name
        attribute :description
        attribute :clearance,   default: :User


        # Validations
        validates :name,        presence: true
        validate  :security_clearance


        attribute :created_at,  default: lambda { Time.now.to_i }


        protected


        def security_clearance
            if self.clearance && CLEARANCE_LEVELS.include?(self.clearance.to_sym)
                self.clearance = self.clearance.to_s
            else
                errors.add(:clearance, 'is not a valid security level')
            end
        end
    end
end
