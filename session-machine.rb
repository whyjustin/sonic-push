require_relative 'clock.rb'

class SessionMachine
  SamplePad = Struct.new(:buffer, :is_playing, :length, :offset, :row, :column)
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @recording_grid = Array.new(8) { |i| Array.new(8) { |j| SamplePad.new(nil, false, nil, 0.0, i, j) } }
    @recording_sample = nil
    @editing_sample = nil
    @recording_length = 4
    @monitor_active = false
    
    @push.clear
    @push.register_note_callback(method(:note_callback))
    @push.register_control_callback(method(:control_callback))
    
    4.times do | length_power |
      length = 2 ** (length_power) * 4
      
      @sonic_pi.live_loop.call "record_#{length}" do
        @sonic_pi.use_bpm.call Clock.bpm
        @sonic_pi.sync.call :master_cue
        
        if @recording_sample != nil and @recording_sample.length == length
          length.times do | i |
            @sonic_pi.sample.call :elec_ping, amp: 2, rate: 0.8 if i % 4 == 0
            @sonic_pi.sample.call :elec_ping, amp: 1 if i % 4 != 0
            @push.color_row_column @recording_sample.row, @recording_sample.column, i % 2 == 1 ? PadColorPallete.red : PadColorPallete.black
            @sonic_pi.sleep.call 1
            
            # Do last tick async to start recording early
            if i == length - 2
              break
            end
          end
          
          @sonic_pi.in_thread.call do
            @sonic_pi.sample.call :elec_ping, amp: 1
            @push.color_row_column @recording_sample.row, @recording_sample.column, PadColorPallete.black
            @sonic_pi.sleep.call 1
            @push.color_row_column @recording_sample.row, @recording_sample.column, PadColorPallete.red
          end
          
          @recording_sample.buffer = @sonic_pi.buffer["sample_#{@recording_sample.row}_#{@recording_sample.column}", length]
          
          @sonic_pi.live_audio.call :mon, :stop
          @sonic_pi.with_fx.call :record, buffer: @recording_sample.buffer do
            @sonic_pi.live_audio.call :rec, stereo: true
          end
          @recording_sample.is_playing = true
          @sonic_pi.sleep.call length
          
          @push.color_row_column @recording_sample.row, @recording_sample.column, PadColorPallete.green
          @sonic_pi.live_audio.call :rec, :stop
          @recording_sample = nil
          
          if @monitor_active
            @sonic_pi.live_audio.call :mon, stereo: true
          end
        else
          @sonic_pi.sleep.call length
        end
      end
    end
    
    4.times do | length_power |
      length = 2 ** (length_power) * 4
      @sonic_pi.live_loop.call "play_#{length}" do
        @sonic_pi.use_bpm.call Clock.bpm
        @sonic_pi.sync.call :master_cue
        
        (2 * length).times do | beat |
          if beat == 2 * length - 2
            @recording_grid.each do | recording_row |
              recording_row.each do | sample |
                if sample.buffer != nil and sample.is_playing and sample.length == length
                  @sonic_pi.sample.call sample.buffer, start: (0.5 * Clock.bpm / 60.0) + sample.offset, sustain: length * Clock.bpm / 60.0
                end
              end
            end
          end
          
          @sonic_pi.sleep.call 0.5
        end
      end
    end
  end
  
  def note_callback(row, column, velocity)
    sample = @recording_grid[row][column]
    if sample.buffer
      sample.is_playing = !sample.is_playing
    end
  end
  
  def control_callback(note, velocity)
    if note == 71
      if @editing_sample != nil
        @editing_sample.offset = @editing_sample.offset + (velocity == 1 ? 0.01 : -0.01)
        print_editing_menu()
      end
    elsif velocity = 127
      if [*36..43].include? note
        record note - 36
      elsif [*102..105].include? note
        @recording_length = (note - 101) * 4
      end
    end
  end
  
  def record(row)
    if @recording_sample != nil
      return
    end
    
    sample = @recording_grid[row].find { | sample | sample.buffer == nil }
    sample.length = @recording_length
    @recording_sample = @editing_sample = sample
    print_editing_menu()
  end
  
  def print_editing_menu()
    if @editing_sample != nil
      @push.clear_display_section(3, 1)
      @push.write_display(3, 1, "Offset #{@editing_sample.offset}")
    end 
  end
end
