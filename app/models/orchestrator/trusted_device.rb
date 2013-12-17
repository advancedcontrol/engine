require 'digest'

module Orchestrator
    class TrustedDevice < Couchbase::Model
        design_document :dev
        include ::CouchbaseId::Generator


        before_create :update_secret


        # The user this device belongs to
        belongs_to :user

        # One time key used to validate the user
        attribute :current_secret
        attribute :previous_secret

        attribute :created_at,      default: lambda { Time.now.to_i }
        attribute :expires
        attribute :last_accessed,   default: lambda { Time.now.to_i }


        # Once the user has saved the new key we remove the old
        def update_confirmed
            previous_secret = nil
            save
        end


        protected


        # Rotates the keys
        def update_secret
            previous_secret = current_secret
            current_secret = Digest::SHA1.hexdigest((Time.now.to_f / (1 + rand(100))).to_s)
            last_accessed = Time.now.to_i
            save
        end

        # Validates the request (user grabbed from encrypted cookie)
        def validate(user_id, key)
            if user_id == self.user_id && (key == current_secret || (!previous_secret.nil? && key == previous_secret))
                current_secret = previous_secret if key == previous_secret
                update_secret
                true
            else
                false
            end
        end


        validates :user,            presence: true
        validates :current_secret,  presence: true
    end
end
