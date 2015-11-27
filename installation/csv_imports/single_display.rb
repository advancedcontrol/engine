# csv filename as argument
# Room #,Model,Equipment Description,Device Qty,Location,Serial Number,MAC Address,VLAN,IP Address,Subnet,Gateway,ACA interface URL
namespace :import do

    desc 'System Import tool for 2015 Abercrombie project'
    task(:learning_hubs_2015, [:file_name, :run_type] => [:environment]) do |task, args|

        f = args[:file_name]
        func = args[:run_type]

        RM_NAME = {
            1010 => 'BSB Learning Hub South',
            1220 => 'BSB Learning Hub North' ,
            1230 => 'BSB Learning Hub East',
            2100 => 'BSB 90P LS',
            3090 => 'BSB 60P LS',
            3100 => 'BSB 60P LS',
            3190 => 'BSB 60P LS',
            3300 => 'BSB 30P LS'
        }
        BLD_ID = {
            1001 => '',
        }
        ZONES = {
            1010 => ["zone_2-17", "zone_2-15", "zone_2-1O", "zone_2-10"],
            1220 => ["zone_2-17", "zone_2-15", "zone_2-1O", "zone_2-10"],
            1230 => ["zone_2-17", "zone_2-15", "zone_2-1O", "zone_2-10"],

            2100 => ["zone_2-1C", "zone_2-1B", "zone_2-1O", "zone_2-10"],
            3090 => ["zone_2-1D", "zone_2-1B", "zone_2-1O", "zone_2-10"],
            3100 => ["zone_2-1E", "zone_2-1B", "zone_2-1O", "zone_2-10"],
            3120 => ["zone_2-1F", "zone_2-1B", "zone_2-1O", "zone_2-10"],
            3190 => ["zone_2-1G", "zone_2-1B", "zone_2-1O", "zone_2-10"],
            3300 => ["zone_2-1H", "zone_2-1B", "zone_2-1O", "zone_2-10"],
        }
        systems = []

        AddSys = Struct.new(
            :room_num, :pod, :display_ip, :display_id, :notes
        ) do
            def system_name
                "#{building_id}.#{room_num} - #{room_name} #{pod.downcase.camelize}"
            end
            
            def room_name
                RM_NAME[room_num]
            end
            
            def building_id
                #BLD_ID[room_num]
                'H70'
            end
            
            def support_url(sys_id)
                "https://control.shared.sydney.edu.au/universal/#/?ctrl=#{sys_id}"
            end
            
            def create!
                sys = Orchestrator::ControlSystem.find_by_name system_name

                unless sys
                    sys = Orchestrator::ControlSystem.new
                    sys.name = system_name
                end
                sys.zones = ZONES[room_num]

                tries = 0
                begin
                    sys.save!
                rescue => e
                    puts "error: #{e.message} -- #{sys.errors.messages}"

                    if tries <= 8
                        sleep 1
                        tries += 1
                        retry
                    else
                        puts "FAILED TO CREATE SYSTEM #{system_name}"
                        return
                    end
                end
                
                dev = Orchestrator::Module.new
                dev.dependency_id = display_id
                dev.ip = display_ip
                dev.notes = notes

                tries = 0
                begin
                    dev.save!
                rescue => e
                    puts "error: #{e.message} -- #{dev.errors.messages}"

                    if tries <= 8
                        sleep 1
                        tries += 1
                        retry
                    else
                        puts "FAILED TO CREATE SYSTEM #{system_name}"
                        return
                    end
                end
                
                logic = Orchestrator::Module.new
                logic.control_system_id = sys.id
                logic.dependency_id = 'dep_2-1A'
                logic.notes = system_name

                tries = 0
                begin
                    logic.save!
                rescue => e
                    puts "error: #{e.message} -- #{logic.errors.messages}"
                    if tries <= 8
                        sleep 1
                        tries += 1
                        retry
                    else
                        puts "FAILED TO CREATE SYSTEM #{system_name}"
                        return
                    end
                end
                
                sys.support_url = support_url(sys.id)
                sys.modules = [logic.id, dev.id]

                tries = 0
                begin
                    sys.save!
                rescue => e
                    puts "error: #{e.message} -- #{sys.errors.messages}"

                    if tries <= 8
                        sleep 1
                        tries += 1
                        retry
                    else
                        puts "FAILED TO CREATE SYSTEM #{system_name}"
                        return
                    end
                end

                puts "Finished creating #{system_name}"
            end
            
            def test
                sys = Orchestrator::ControlSystem.find_by_name system_name

                unless sys
                    puts "NEW Building: #{system_name}"
                    sys = Orchestrator::ControlSystem.new
                    sys.name = system_name
                else
                    puts "EXI Building: #{system_name}"
                end
                sys.zones = ZONES[room_num]
                
                dev = Orchestrator::Module.new
                dev.dependency_id = display_id
                dev.ip = display_ip
                dev.notes = notes
                
                logic = Orchestrator::Module.new
                logic.control_system_id = sys.id
                logic.dependency_id = 'dep_2-1A'
            end
        end

        # read line by line
        File.foreach(f).with_index do |line, line_num|
            # skip first line (headings)
            next if line_num == 0 || line.strip.empty?
            raw = line.split(",")
            next if raw[1] =~ /ipad/i
                
            system = AddSys.new
            system.room_num = raw[0].to_i
            system.display_ip = raw[8]
            system.notes = "Subnet: #{raw[9]}\nGateway: #{raw[10]}\nMAC Address: #{raw[6]}\nSerial: #{raw[5]}\nVLAN: #{raw[7]}"
            system.pod = raw[4]
            
            if raw[1] =~ /^"*PN/i
                # Sharp Display
                system.display_id = 'dep_2-17'
            else
                # NEC Display
                system.display_id = 'dep_2-15'
            end
            
            systems << system
        end

        if func != 'create!'
            func = :test
        else
            func = :create!
        end
        systems.each {|sys| sys.send(func)}
    end
end
