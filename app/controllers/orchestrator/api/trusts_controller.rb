
module Orchestrator
    module Api
        class TrustsController < ApiController
            respond_to :json
            doorkeeper_for :index #:all, :except => :show

            # List current trusts for the user
            def index
                render text: 'Hello Auth!'
            end

            # Used to trust the current device
            # TODO:: protect create and destroy with doorkeeper
            def create
                user = current_user
                if user.nil?
                    render nothing: true, status: :unauthorized
                else
                    trust = TrustedDevice.new
                    trust.user_id = user.id
                    trust.update_secret # this saves the trust
                    render json: {secret: trust.current_secret}
                end
            end

            # Destroy a trust
            def destroy
                trust = TrustedDevice.find_by_id(id)
                if trust.nil?
                    actual = TrustedDevice.bucket.get("trustkey-#{id}")
                    trust = TrustedDevice.find(actual)
                end

                # TODO:: allow admins to destroy trusts
                if trust.user_id == current_user.id
                    trust.remove
                    render nothing: true
                else
                    # TODO:: log request here
                    render nothing: true, status: :forbidden
                end
            end

            # This is used to build a new session
            def show
                trust = TrustedDevice.find(TrustedDevice.bucket.get("trustkey-#{id}"))
                trust.update_secret

                # TODO:: build the session
                # OR replace with refresh tokens!!!

                render json: {secret: trust.current_secret}
            end

            # confirms the trust and removes the old key
            def update
                trust = TrustedDevice.find(TrustedDevice.bucket.get("trustkey-#{id}"))
                trust.update_confirmed
                render nothing: true
            end


            protected


            def check_user
                # TODO:: ensure user is
            end
        end
    end
end
