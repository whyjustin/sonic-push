class Clock
  @@bpm = 60
  
  def initialize(sonic_pi, push)
    @enable = false
    @monitor_active = false
    @beats = [2,0,1,0,1,0,1,0]
    
    sonic_pi.live_loop.call :metronome do
      sonic_pi.use_bpm.call @@bpm
      sonic_pi.sync.call :master_cue
      push.register_control_callback(method(:control_callback))
      
      if @enable
        beat = @beats.ring.tick
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
  
  def self.bpm
    @@bpm
  end
  
  def control_callback(note, velocity)
    if velocity == 127
      if note == 9
        @enable = !@enable
      elsif note == 3
        @monitor_active = !@monitor_active
      end
    end
  end
end
