class Clock
  @@bpm = 60
  
  def initialize(sonic_pi, push)
    @push = push
    print_bpm()
    
    @enable = false
    @monitor_active = false
    @beats = [2,0,1,0,1,0,1,0]
    
    @push.register_control_callback(method(:control_callback))
    
    sonic_pi.live_loop.call :metronome do
      sonic_pi.use_bpm.call @@bpm
      sonic_pi.cue.call :master_cue
      
      8.times do | i |
        if @enable
          beat = @beats[i]
          sonic_pi.sample.call :elec_tick, amp: 1, rate: 0.8 if beat == 1
          sonic_pi.sample.call :elec_tick, amp: 2 if beat == 2
        end
        if @monitor_active
          sonic_pi.live_audio.call :mon, stereo: true
        else
          sonic_pi.live_audio.call :mon, :stop
        end
        sonic_pi.sleep.call 0.5
      end
    end
  end
  
  def self.bpm
    @@bpm
  end
  
  def self.bpm=bpm
    @@bpm = @@bpm
  end
  
  def control_callback(note, velocity)
    if note == 14 # tempo
      @@bpm = @@bpm + (velocity == 1 ? 1 : -1)
      print_bpm()
    elsif velocity == 127
      if note == 9
        @enable = !@enable
      elsif note == 3
        @monitor_active = !@monitor_active
      end
    end
  end
  
  def print_bpm()
    @push.clear_display_section(3, 0)
    @push.write_display(3, 0, "BPM: #{@@bpm}")
  end
end