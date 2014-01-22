require 'set'


module Orchestrator
    module Constants
        On = true       # On is active
        Off = false     # Off is inactive
        Down = true     # Down is usually active
        Up = false      # Up is usually not in use

        On_vars = Set.new([1, true, 'true', 'True', :on, :On, 'on', 'On', :yes, :Yes, 'yes', 'Yes'])
        Off_vars = Set.new([0, false, 'false', 'False', :off, :Off, 'off', 'Off', :no, :No, 'no', 'No'])


        def in_range(num, max, min = 0)
            num = min if num < min
            num = max if num > max
            num
        end

        def is_affirmative?(val)
            On_vars.include?(val)
        end

        def is_negatory?(val)
            Off_vars.include?(val)
        end
    end
end
