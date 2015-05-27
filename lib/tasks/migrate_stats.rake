namespace :migrate do

    desc 'Migrate modules so that statistics queryies are accurate'

    task :stats => :environment do
        # This adds support for statistics collection via elasticsearch

        ::Orchestrator::Module.all.each do |mod|
            mod.ignore_connected = false
            mod.save!
        end
    end

end
