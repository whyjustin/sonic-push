require_relative 'clock.rb'
require_relative 'helper.rb'
require_relative 'color-palette.rb'

class SessionMachine
  Mixer = Struct.new(:hpf, :lpf)
  
  @@recording_bar_options = 4
  @@current_bar = 0
  @@viewing_bar = 0
  @@recording_bar_power = 0
  @@retrigger = nil
  
  def self.recording_bar_options
    return @@recording_bar_options
  end
  
  def self.current_bar
    return @@current_bar
  end
  
  def self.recording_bar_power
    return @@recording_bar_power
  end
  
  def self.recording_bars
    return 2 ** @@recording_bar_power
  end
  
  def self.steps_per_bar
    return 4
  end
  
  def self.recording_steps
    return self.recording_bars * self.steps_per_bar
  end
  
  def self.viewing_bar
    return @@viewing_bar
  end
  
  def self.retrigger
    return @@retrigger
  end
  
  def initialize(sonic_pi, push, sampler, drum_machine)
    @sonic_pi = sonic_pi
    @push = push
    @sampler = sampler
    @drum_machine = drum_machine
    @push.clear
    
    @mixer = Mixer.new(0, 131)
    @sonic_pi.set_mixer_control.call lpf: @mixer.lpf
    @sonic_pi.set_mixer_control.call hpf: @mixer.hpf
    
    @recording_bar_highlights = [
      [ [ 0 ] ],
      [ [ 0 ], [ 1 ] ],
      [ [ 0 ], [ 0, 1 ], [ 1, 2 ], [ 2 ] ],
      [ [ 0 ], [ 0, 1 ], [ 0, 2 ], [ 1 ], [ 2 ], [ 1, 3 ], [ 2, 3 ], [ 3 ] ]
    ]
    set_recording_bar_power 0
    
    @mode = :SESSION_MODE
    print_editing_menu()

    @is_recording = false
    @save_location = nil
    
    @sonic_pi.live_loop.call :session_clock do
      @@current_bar = @@current_bar == 2 ** (@@recording_bar_options - 1) ? 1 : @@current_bar + 1
      color_recording_bars()
      
      @sonic_pi.use_bpm.call Clock.bpm
      @sonic_pi.sync.call :master_cue
      
      8.times do | i |
        @push.clear_second_strip()
        @push.color_second_strip(i, SecondStripColorPalette.white)
        
        @sonic_pi.sleep.call 0.5
      end
    end
    
    @sonic_pi.live_loop.call :sampler do
      @sonic_pi.use_bpm.call Clock.bpm
      @sonic_pi.sync.call :master_cue
      
      sampler.play @@current_bar
    end
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_note_callback(method(:note_callback))
    @push.register_control_callback(method(:control_callback))
    @push.register_pitch_callback(method(:pitch_callback))
  end

  def set_save_location(save_location)
    @save_location = save_location
    @push.color_note 86, NoteColorPalette.dim
  end
  
  def pad_callback(row, column, velocity)
    if not @mode == :SESSION_MODE
      return
    end
    
    if row == 0
      drum_track_index = row * 8 + column
      drum_track = @drum_machine.drum_tracks[drum_track_index]
      if !drum_track.is_playing
        if drum_track.bars != nil
          set_recording_bar_power (Math::log(drum_track.bars) / Math::log(2)).to_i
        end
        
        @drum_machine.edit drum_track_index
        switch_mode :DRUM_MODE
      end
      @drum_machine.toggle_play drum_track_index
    elsif [*2..5].include? row
      @sampler.arm_edit_or_play(row - 2, column)
    end
  end
  
  def control_callback(note, velocity)
    if velocity == 127
      if [*20..20 + @@recording_bar_options].include? note
        power = (note - 19) - 1
        set_recording_bar_power power
      elsif note == 44
        set_viewing_bar(@@viewing_bar > 0 ? @@viewing_bar - 1 : @@viewing_bar)
      elsif note == 45
        set_viewing_bar(@@viewing_bar < SessionMachine.recording_bars - 1 ? @@viewing_bar + 1 : @@viewing_bar)
      elsif note == 51
        @sampler.clear_editing_sample()
        switch_mode :SESSION_MODE
      elsif note == 86
        if @save_location != nil
          if !@is_recording
            @is_recording = true
            @sonic_pi.osc_send.call 'localhost', 4557, '/start-recording', 'sonic-push'
            @push.color_note 86, NoteColorPalette.lit
          else
            @sonic_pi.osc_send.call 'localhost', 4557, '/stop-recording', 'sonic-push'
            @push.color_note 86, NoteColorPalette.dim
            @sonic_pi.sleep.call 0.5
            @sonic_pi.osc_send.call 'localhost', 4557, '/save-recording', 'sonic-push', "#{@save_location}/sonic-push.wav"
          end
        end
      end
    end
    if note == 78
      @mixer.lpf = Helper.within(@mixer.lpf + (velocity == 1 ? 1.0 : -1.0), 0, 131).round(0)
      @sonic_pi.set_mixer_control.call lpf: @mixer.lpf
      print_editing_menu()
    elsif note == 79
      @mixer.hpf = Helper.within(@mixer.hpf + (velocity == 1 ? 1.0 : -1.0), 0, 131).round(0)
      @sonic_pi.set_mixer_control.call hpf: @mixer.hpf
      print_editing_menu()
    end
  end
  
  def note_callback(note, velocity)
    if velocity == 0 and note == 12
      @@retrigger = nil
    end
  end
  
  def pitch_callback(pitch)
    # Pitch defaults to 8192 when letting go
    if pitch == 8192
      return
    elsif pitch > 10000
      @@retrigger = 8
    elsif pitch > 6600
      @@retrigger = 4
    elsif pitch > 3300
      @@retrigger = 2
    else
      @@retrigger = 1
    end
  end
  
  def set_recording_bar_power(bar_power)
    @@recording_bar_power = bar_power
    color_recording_bars
    @drum_machine.set_recording_bar_power
    set_viewing_bar @@viewing_bar >= SessionMachine.recording_bars ? SessionMachine.recording_bars - 1 : @@viewing_bar
  end
  
  def color_recording_bars()
    highlighted_bar_options = @recording_bar_highlights[@@recording_bar_power]
    highlighted_bars = highlighted_bar_options[@@current_bar % highlighted_bar_options.length]
    @@recording_bar_options.times do | recording_bar_option |
      if !highlighted_bars.include? recording_bar_option
        if recording_bar_option <= @@recording_bar_power
          @push.color_first_strip recording_bar_option, FirstStripColorPalette.orange
        else
          @push.color_first_strip recording_bar_option, FirstStripColorPalette.black
        end
      end
    end
    
    highlighted_bars.each do | highlighted_bar |
      @push.color_first_strip highlighted_bar, FirstStripColorPalette.orange_blink_fast
    end
  end
  
  def set_viewing_bar(viewing_bar)
    if @mode == :DRUM_MODE
      @@viewing_bar = viewing_bar
      @push.color_note 44, @@viewing_bar != 0 ? NoteColorPalette.lit : NoteColorPalette.off
      @push.color_note 45, @@viewing_bar != SessionMachine.recording_bars - 1 ? NoteColorPalette.lit : NoteColorPalette.off
      @drum_machine.set_viewing_bar
    else
      @push.color_note 44, NoteColorPalette.off
      @push.color_note 45, NoteColorPalette.off
    end
  end
  
  def switch_mode(mode)
    @mode = mode
    set_viewing_bar 0
    
    case mode
    when :DRUM_MODE
      # Set active mode to true to prevent coloring playing pads
      @drum_machine.is_active_mode = true
      @push.clear
      @sonic_pi.sleep.call 0.1
      
      @sampler.is_active_mode = false
      # Set active mode to true to configure active mode
      @drum_machine.is_active_mode = true
      @push.color_note 51, NoteColorPalette.dim
    when :SESSION_MODE
      @push.clear
      @sonic_pi.sleep.call 0.1
      
      @drum_machine.is_active_mode = false
      print_editing_menu()
      @sampler.is_active_mode = true
      @push.color_note 51, NoteColorPalette.lit
    end
  end
  
  def print_editing_menu()
    clear_editing_menu()
    @sonic_pi.sleep.call 0.1
    @push.write_display(0, 3, "Global")
    @push.write_display(1, 3, "LPF #{@mixer.lpf}")
    @push.write_display(2, 3, "HPF #{@mixer.hpf}")
  end
  
  def clear_editing_menu()
    @push.clear_display_section(0, 3)
    @push.clear_display_section(1, 3)
    @push.clear_display_section(2, 3)
  end
end
