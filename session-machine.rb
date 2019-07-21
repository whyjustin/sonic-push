require_relative 'clock.rb'


class SessionMachine
  SamplePad = Struct.new(:buffer, :is_playing, :bars, :amp, :row, :column)
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    @push.clear
    
    @recording_grid = Array.new(8) { |i| Array.new(8) { |j| SamplePad.new(nil, false, nil, 4.0, i, j) } }
    @recording_sample = nil
    @editing_sample = nil
    @monitor_active = false
    
    @recording_bar_options = 4
    @recording_bar_highlights = [
      [ [ 0 ] ],
      [ [ 0 ], [ 1 ] ],
      [ [ 0 ], [ 0, 1 ], [ 1, 2 ], [ 2 ] ],
      [ [ 0 ], [ 0, 1 ], [ 0, 2 ], [ 1 ], [ 2 ], [ 1, 3 ], [ 2, 3 ], [ 3 ] ]
    ]
    @current_bar = 0
    set_recording_bar_power 1
    
    @is_active_mode = true
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_control_callback(method(:control_callback))
    
    @sonic_pi.live_loop.call "record" do
      @sonic_pi.use_bpm.call Clock.bpm
      @sonic_pi.sync.call :master_cue
      
      if @recording_sample != nil
        recording_bars = 2 ** (@recording_bar_power - 1)
        if @current_bar % @recording_sample.bars == @recording_sample.bars - 1
          recording_beats = @recording_sample.bars * 4
          @recording_sample.buffer = @sonic_pi.buffer["sample_#{@recording_sample.row}_#{@recording_sample.column}", recording_beats]
          
          4.times do | i |
            @sonic_pi.sample.call :elec_ping, amp: 2, rate: 0.8 if i % 4 == 0
            @sonic_pi.sample.call :elec_ping, amp: 1 if i % 4 != 0
            color_sample @recording_sample, i % 2 == 0 ? PadColorPallete.red : PadColorPallete.black
            @sonic_pi.sleep.call 1
          end
          
          @sonic_pi.sync.call :master_cue
          color_sample @recording_sample, PadColorPallete.red
          
          reactivate_monitor = @monitor_active
          @monitor_active = false
          @sonic_pi.cue.call :monitor_cue
          
          @sonic_pi.with_fx.call :record, buffer: @recording_sample.buffer do
            @sonic_pi.live_audio.call :rec, amp: 4, stereo: true
          end
          
          @sonic_pi.sleep.call recording_bars * 4
          
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
    
    @sonic_pi.live_loop.call "play" do
      @current_bar = @current_bar == 2 ** (@recording_bar_options - 1) ? 1 : @current_bar + 1
      color_recording_bars()
      
      @sonic_pi.use_bpm.call Clock.bpm
      @sonic_pi.sync.call :master_cue
      
      @recording_grid.each do | recording_row |
        recording_row.each do | sample |
          if sample.bars != nil
            if @current_bar % sample.bars == 0 and sample != @recording_sample
              if sample.buffer != nil and sample.is_playing
                color_sample sample, PadColorPallete.green
                @sonic_pi.sample.call sample.buffer, amp: sample.amp
              elsif
                color_sample sample, PadColorPallete.black
              end
            end
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
  
  def is_active_mode=is_active_mode
    if is_active_mode
      color_recording_bars()
      
      @recording_grid.each do | recording_row |
        recording_row.each do | sample |
          if sample.is_playing
            color_sample sample, PadColorPallete.green
          end
        end
      end
    end
    @is_active_mode = is_active_mode
  end
  
  def pad_callback(row, column, velocity)
    if not @is_active_mode
      return
    end
    
    sample = @recording_grid[row][column]
    if sample.buffer
      color_sample sample, PadColorPallete.grey
      @editing_sample = sample
      sample.is_playing = !sample.is_playing
    else
      record row, column
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
      if [*20..20 + @recording_bar_options].include? note
        bars = (note - 19)
        set_recording_bar_power bars
      elsif note == 3
        @monitor_active = !@monitor_active
        @sonic_pi.cue.call :monitor_cue
      end
    end
  end
  
  def record(row, column)
    if @recording_sample != nil
      return
    end
    
    sample = @recording_grid[row][column]
    sample.bars = 2 ** (@recording_bar_power - 1)
    @recording_sample = @editing_sample = sample
    
    color_sample @recording_sample, PadColorPallete.red
    print_editing_menu()
  end
  
  def color_sample(recording_sample, color)
    if not @is_active_mode
      return
    end
    
    @push.color_row_column recording_sample.row, recording_sample.column, color
  end
  
  def set_recording_bar_power(bar_power)
    @recording_bar_power = bar_power
    color_recording_bars
  end
  
  def color_recording_bars()
    if not @is_active_mode
      return
    end
    
    highlighted_bar_options = @recording_bar_highlights[@recording_bar_power - 1]
    highlighted_bars = highlighted_bar_options[@current_bar % highlighted_bar_options.length - 1]
    @recording_bar_options.times do | recording_bar_option |
      if !highlighted_bars.include? recording_bar_option
        if recording_bar_option < @recording_bar_power
          @push.color_second_strip recording_bar_option, SecondStripColorPallete.orange
        else
          @push.color_second_strip recording_bar_option, SecondStripColorPallete.black
        end
      end
    end
    
    highlighted_bars.each do | highlighted_bar |
      @push.color_second_strip highlighted_bar, SecondStripColorPallete.orange_blink_fast
    end
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
