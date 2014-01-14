require 'set'


module Orchestrator
    module Constants
        On = true       # On is active
        Off = false     # Off is inactive
        Down = true     # Down is usually active
        Up = false      # Up is usually not in use

        On_vars = Set.new([1, true, :on, :On, 'on', 'On'])
        Off_vars = Set.new([0, false, :off, :Off, 'off', 'Off'])


        def in_range(num, max, min = 0)
            num = min if num < min
            num = max if num > max
            num
        end

        def is_affirmative?(val)
            On_vars.include?(val)
        end
    end
end
