require_relative 'color-palette.rb'
require_relative 'session-machine.rb'

class Sampler
  SamplePad = Struct.new(:buffer, :is_playing, :bars, :amp, :row, :column)
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @recording_grid = Array.new(4) { |i| Array.new(8) { |j| SamplePad.new(nil, false, nil, 4.0, i, j) } }
    @recording_sample = nil
    @editing_sample = nil
    @monitor_active = false
    @is_active_mode = true
    
    @push.register_control_callback(method(:control_callback))
    
    @sonic_pi.live_loop.call "record" do
      @sonic_pi.use_bpm.call Clock.bpm
      @sonic_pi.sync.call :master_cue
      
      if @recording_sample != nil
        if SessionMachine.current_bar % @recording_sample.bars == @recording_sample.bars - 1
          recording_beats = @recording_sample.bars * 4
          @recording_sample.buffer = @sonic_pi.buffer["sample_#{@recording_sample.row}_#{@recording_sample.column}", recording_beats]
          
          4.times do | i |
            @sonic_pi.sample.call :elec_ping, amp: 2, rate: 0.8 if i % 4 == 0
            @sonic_pi.sample.call :elec_ping, amp: 1 if i % 4 != 0
            color_sample @recording_sample, i % 2 == 0 ? PadColorPalette.red : PadColorPalette.black
            @sonic_pi.sleep.call 1
          end
          
          @sonic_pi.sync.call :master_cue
          color_sample @recording_sample, PadColorPalette.red
          
          reactivate_monitor = @monitor_active
          @monitor_active = false
          @sonic_pi.cue.call :monitor_cue
          
          @sonic_pi.with_fx.call :record, buffer: @recording_sample.buffer do
            @sonic_pi.live_audio.call :rec, amp: 4, stereo: true
          end
          
          @sonic_pi.sleep.call SessionMachine.recording_bars * 4
          
          @sonic_pi.live_audio.call :rec, :stop
          @recording_sample.is_playing = true
          @recording_sample = nil
          
          if reactivate_monitor
            @monitor_active = true
            @sonic_pi.cue.call :monitor_cue
          end
        end
      end
    end
    
    @sonic_pi.live_loop.call :monitor do
      # Monitor in it's own loop waiting for a change to @monitor_active and a cue
      @sonic_pi.sync.call :monitor_cue
      if @monitor_active
        @sonic_pi.live_audio.call :mon, amp: 4, stereo: true
      else
        @sonic_pi.live_audio.call :mon, :stop
      end
      @sonic_pi.sleep.call 0.5
    end
  end
  
  def play(bar)
    @recording_grid.each do | recording_row |
      recording_row.each do | sample |
        if sample.bars != nil
          if bar % sample.bars == 0 and sample != @recording_sample
            if sample.buffer != nil and sample.is_playing
              color_sample sample, PadColorPalette.green
              @sonic_pi.sample.call sample.buffer, amp: sample.amp
            elsif
              color_sample sample, PadColorPalette.black
            end
          end
        end
      end
    end
  end
  
  def control_callback(note, velocity)
    if not @is_active_mode
      return
    end
    
    if note == 71
      if @editing_sample != nil
        @editing_sample.amp = @editing_sample.amp + (velocity == 1 ? 0.01 : -0.01)
        print_editing_menu()
      end
    elsif velocity = 127
      if note == 3
        @monitor_active = !@monitor_active
        @sonic_pi.cue.call :monitor_cue
      end
    end
  end
  
  def is_active_mode=is_active_mode
    if is_active_mode
      @recording_grid.each do | recording_row |
        recording_row.each do | sample |
          if sample.is_playing
            color_sample sample, PadColorPalette.green
          end
        end
      end
    end
    @is_active_mode = is_active_mode
  end
  
  def arm_or_play(row, column)
    sample = @recording_grid[row][column]
    if sample.buffer
      color_sample sample, PadColorPalette.grey
      editing_sample = sample
      sample.is_playing = !sample.is_playing
    else
      record row, column
    end
  end
  
  def record(row, column)
    if @recording_sample != nil
      return
    end
    
    sample = @recording_grid[row][column]
    sample.bars = SessionMachine.recording_bars
    @recording_sample = @editing_sample = sample
    
    color_sample @recording_sample, PadColorPalette.red
    print_editing_menu()
  end
  
  def color_sample(recording_sample, color)
    if not @is_active_mode
      return
    end
    
    @push.color_row_column recording_sample.row, recording_sample.column, color
  end
  
  def print_editing_menu()
    if not @is_active_mode
      return
    end
    
    if @editing_sample != nil
      @push.clear_display_section(3, 1)
      @push.write_display(3, 1, "Amp #{@editing_sample.amp}")
    end
  end
end
