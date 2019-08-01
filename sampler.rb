require_relative 'color-palette.rb'
require_relative 'session-machine.rb'


class Sampler
  SamplePad = Struct.new(:buffer, :is_playing, :bars, :amp, :mode, :row, :column)
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @recording_grid = Array.new(4) { |i| Array.new(8) { |j| SamplePad.new(nil, false, nil, 2.0, :PLAY, i + 2, j) } }
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
              retrigger = SessionMachine.retrigger
              if retrigger != nil and (@editing_sample == nil or sample == @editing_sample)
                @sonic_pi.in_thread.call do
                  steps = 8.0 * sample.bars
                  (steps / retrigger).times do
                    @sonic_pi.sample.call sample.buffer, amp: sample.amp, start: 0, finish: retrigger / steps
                    @sonic_pi.sleep.call retrigger / 2.0
                  end
                end
              else
                if [:PLAY, :BACK].include? sample.mode
                  @sonic_pi.sample.call sample.buffer, amp: sample.amp, rate: sample.mode == :PLAY ? 1 : -1
                else
                  @sonic_pi.in_thread.call do
                    steps = 4 * sample.bars
                    steps.times do | step |
                      slice_idx = rand(steps - 1)
                      slice_size = 1.0 / steps
                      start = slice_idx * slice_size
                      finish = start + slice_size
                      @sonic_pi.sample.call sample.buffer, amp: sample.amp, start: start, finish: finish, rate: (sample.mode == :SLICE or (sample.mode == :SLIDE_RAND and rand(1) == 1) ? 1 : -1)
                      @sonic_pi.sleep.call 1
                    end
                  end
                end
              end
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
        @editing_sample.amp = (@editing_sample.amp + (velocity == 1 ? 0.01 : -0.01)).round(2)
        print_editing_menu()
      end
    elsif note == 72
      if @editing_sample != nil
        @editing_sample.mode = next_mode(@editing_sample.mode)
        print_editing_menu()
      end
    elsif velocity = 127
      if note == 3
        @monitor_active = !@monitor_active
        @sonic_pi.cue.call :monitor_cue
      end
    end
  end
  
  def next_mode(mode)
    case mode
    when :PLAY
      return :SLICE
    when :SLICE
      return :SLICE_BACK
    when :SLICE_BACK
      return :SLICE_RAND
    when :SLICE_RAND
      return :BACK
    when :BACK
      return :PLAY
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
    else
      clear_editing_sample()
    end
    @is_active_mode = is_active_mode
  end
  
  def clear_editing_sample
    @editing_sample = nil
  end
  
  def arm_edit_or_play(row, column)
    sample = @recording_grid[row][column]
    if sample != @editing_sample
      @editing_sample = sample
      print_editing_menu()
    elsif sample.buffer
      color_sample sample, PadColorPalette.grey
      @editing_sample = sample
      sample.is_playing = !sample.is_playing
      print_editing_menu()
      
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
    
    clear_editing_menu()
    if @editing_sample != nil
      @push.write_display(0, 1, "Sample")
      @push.write_display(1, 1, "Amp #{@editing_sample.amp}")
      @push.write_display(2, 1, "Mode #{@editing_sample.mode.to_s}")
    end
  end
  
  def clear_editing_menu()
    @push.clear_display_section(0, 1)
    @push.clear_display_section(1, 1)
    @push.clear_display_section(2, 1)
  end
end
