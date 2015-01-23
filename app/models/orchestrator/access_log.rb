
module Orchestrator
    class AccessLog < Couchbase::Model
        design_document :alog
        include ::CouchbaseId::Generator


        TTL = Rails.env.production? ? 2.weeks.to_i : 120


        belongs_to :user,      class_name: "::User"
        attribute  :systems,   default: lambda { [] }

        attribute :persisted,  default: false
        attribute :suspected,  default: false
        attribute :notes

        attribute :created_at
        attribute :ended_at


        def initialize(*args)
            super(*args)
            self.created_at = Time.now.to_i
        end

        def save
            if self.persisted
                super
            else
                super(ttl: TTL)
            end
        end
    end
end
