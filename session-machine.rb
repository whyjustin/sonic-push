require_relative 'clock.rb'

class SessionMachine
  @@recording_bar_options = 4
  @@current_bar = 0
  @@viewing_bar = 0
  @@recording_bar_power = 0
  
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
  
  def initialize(sonic_pi, push, sampler, drum_machine)
    @sonic_pi = sonic_pi
    @push = push
    @sampler = sampler
    @drum_machine = drum_machine
    @push.clear
    
    @recording_bar_highlights = [
      [ [ 0 ] ],
      [ [ 0 ], [ 1 ] ],
      [ [ 0 ], [ 0, 1 ], [ 1, 2 ], [ 2 ] ],
      [ [ 0 ], [ 0, 1 ], [ 0, 2 ], [ 1 ], [ 2 ], [ 1, 3 ], [ 2, 3 ], [ 3 ] ]
    ]
    set_recording_bar_power 0
    
    @mode = :SESSION_MODE
    
    @sonic_pi.live_loop.call "play" do
      @@current_bar = @@current_bar == 2 ** (@@recording_bar_options - 1) ? 1 : @@current_bar + 1
      color_recording_bars()
      
      @sonic_pi.use_bpm.call Clock.bpm
      @sonic_pi.sync.call :master_cue
      
      sampler.play @@current_bar
      drum_machine.play @@current_bar
      
      8.times do | i |
        @push.clear_second_strip()
        @push.color_second_strip(i, SecondStripColorPalette.white)
        
        @sonic_pi.sleep.call 0.5
      end
    end
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  def pad_callback(row, column, velocity)
    if not @mode == :SESSION_MODE
      return
    end
    
    if [*0..1].include? row
      drum_track_index = row * 8 + column
      drum_track = @drum_machine.drum_tracks[drum_track_index]
      if !drum_track.is_playing
        if drum_track.bars != nil
          set_recording_bar_power (Math::log(drum_track.bars) / Math::log(2)).to_i - 1
        end

        @drum_machine.edit drum_track_index
        switch_mode :DRUM_MODE
      end
      @drum_machine.toggle_play drum_track_index
    elsif [*2..5].include? row
      @sampler.arm_or_play(row - 2, column)
    end
  end
  
  def control_callback(note, velocity)
    if velocity = 127
      if [*20..20 + @@recording_bar_options].include? note
        power = (note - 19) - 1
        set_recording_bar_power power
      elsif note == 44
        set_viewing_bar(@@viewing_bar > 0 ? @@viewing_bar - 1 : @@viewing_bar)
      elsif note == 45
        set_viewing_bar(@@viewing_bar < SessionMachine.recording_bars - 1 ? @@viewing_bar + 1 : @@viewing_bar)
      elsif note == 51
        switch_mode :SESSION_MODE
      end
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
    case mode
    when :DRUM_MODE
      @push.clear
      @sonic_pi.sleep.call 0.1
      
      @sampler.is_active_mode = false
      @drum_machine.is_active_mode = true
      set_viewing_bar 0
      @push.color_note 51, NoteColorPalette.dim
    when :SESSION_MODE
      @push.clear
      @sonic_pi.sleep.call 0.1
      
      @drum_machine.is_active_mode = false
      @sampler.is_active_mode = true
      @push.color_note 51, NoteColorPalette.lit
    end
  end
end
