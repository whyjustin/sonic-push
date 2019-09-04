class Clock
  @@bpm = 90
  
  def initialize(sonic_pi, push)
    @push = push
    print_bpm()
    
    @enable = false
    @beats = [2,0,1,0,1,0,1,0]
    
    @push.register_control_callback(method(:control_callback))
    
    sonic_pi.live_loop.call :metronome do
      sonic_pi.use_bpm.call @@bpm
      sonic_pi.cue.call :master_cue
      
      8.times do | i |
        if i % 2 == 0
          sonic_pi.midi_clock_beat.call
        end
        if @enable
          beat = @beats[i]
          sonic_pi.sample.call :elec_tick, amp: 1, rate: 0.8 if beat == 1
          sonic_pi.sample.call :elec_tick, amp: 2 if beat == 2
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
      end
    end
  end
  
  def print_bpm()
    @push.write_display(3, 0, "BPM #{@@bpm}")
  end
end
