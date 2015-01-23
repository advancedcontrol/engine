
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
        attribute :last_checked_at, default: 0


        def initialize(*args)
            super(*args)

            if self.created_at.nil?
                self.created_at = Time.now.to_i
            end
        end

        def save
            self.last_checked_at = Time.now.to_i

            if self.persisted
                super
            else
                super(ttl: TTL)
            end
        end
    end
end
