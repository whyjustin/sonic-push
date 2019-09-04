require_relative 'clock.rb'
require_relative 'helper.rb'
require_relative 'color-palette.rb'

class SessionMachine
  Mixer = Struct.new(:hpf, :lpf)
  
  @@recording_bar_options = 4
  @@current_bar = 0
  @@recording_bar_power = 0
  @@retrigger = nil

  @@mode = :SESSION_MODE

  def self.recording_bar_options
    return @@recording_bar_options
  end

  def self.current_bar
    return @@current_bar
  end

  def self.recording_bar_power
    return @@recording_bar_power
  end

  def self.retrigger
    return @@retrigger
  end

  def self.mode
    return @@mode
  end
  
  def self.recording_bars
    return 2 ** @@recording_bar_power
  end
  
  def self.steps_per_bar
    return 8
  end

  # System based configuration
  @@latency = 0.0
  @@recording_pre_amp = 0.0
  @@mute_while_recording = false

  def self.latency
    return @@latency
  end

  def self.latency=latency
    @@latency = latency
  end
  
  def self.recording_pre_amp
    return @@recording_pre_amp
  end

  def self.recording_pre_amp=recording_pre_amp
    @@recording_pre_amp = recording_pre_amp
  end

  def self.mute_while_recording
    return @@mute_while_recording
  end

  def self.mute_while_recording=mute_while_recording
    @@mute_while_recording = mute_while_recording
  end

  def initialize(sonic_pi, push, sampler, chop_sampler, drum_machine, synthesizer)
    @sonic_pi = sonic_pi
    @push = push
    @sampler = sampler
    @chop_sampler = chop_sampler
    @drum_machine = drum_machine
    @synthesizer = synthesizer
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
    
    switch_mode(:SESSION_MODE)

    @is_recording = false
    @monitor_active = false
    @save_location = nil
    @edit_modifier_pressed = false
    
    @sonic_pi.live_loop.call :session_clock do
      @@current_bar = @@current_bar == (2 ** @@recording_bar_options) - 1 ? 0 : @@current_bar + 1
      color_recording_bars()
      
      @sonic_pi.use_bpm.call Clock.bpm
      @sonic_pi.sync.call :master_cue
      
      8.times do | i |
        @push.clear_second_strip()
        @push.color_second_strip(i, SecondStripColorPalette.white)
        
        @sonic_pi.sleep.call 0.5
      end
    end
    
    @sonic_pi.live_loop.call :session_play do
      @sonic_pi.use_bpm.call Clock.bpm
      @sonic_pi.sync.call :master_cue
      
      sampler.play @@current_bar
      synthesizer.play @@current_bar
    end

    @sonic_pi.live_loop.call :monitor do
      # Monitor in it's own loop waiting for a change to @monitor_active
      if @monitor_active
        @sonic_pi.live_audio.call :mon, stereo: true
      else
        @sonic_pi.live_audio.call :mon, :stop
      end
      @sonic_pi.sleep.call 0.5
    end
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_pad_off_callback(method(:pad_off_callback))
    @push.register_note_callback(method(:note_callback))
    @push.register_control_callback(method(:control_callback))
    @push.register_pitch_callback(method(:pitch_callback))
  end

  def set_save_location(save_location)
    @save_location = save_location
    @push.color_note 86, NoteColorPalette.dim
  end
  
  def pad_callback(row, column, velocity)
    if not @@mode == :SESSION_MODE
      return
    end
    
    if [*0..(AbletonPush.drum_row_size() - 1)].include? row
      drum_track_index = row * 8 + column
      drum_track = @drum_machine.drum_tracks[drum_track_index]
      if drum_track.bars == nil or @edit_modifier_pressed
        if drum_track.bars != nil
          set_recording_bar_power (Math::log(drum_track.bars) / Math::log(2)).to_i
        else
          @drum_machine.toggle_play(drum_track_index)
        end
        @drum_machine.edit drum_track_index
        switch_mode :DRUM_MODE
      else
        @drum_machine.toggle_play(drum_track_index)
      end
    elsif [*AbletonPush.drum_row_size()..(AbletonPush.drum_row_size() + AbletonPush.chop_sample_row_size() - 1)].include? row
      chop_track_index = row * 8 + column - AbletonPush.pad_column_size() * AbletonPush.drum_row_size()
      chop_track = @chop_sampler.chop_samples[chop_track_index]
      if chop_track == nil or chop_track.buffer == nil
        @chop_sampler.begin_record(chop_track_index)
      elsif @edit_modifier_pressed
        @chop_sampler.edit(chop_track_index)
        switch_mode :CHOP_MODE
      else
        @chop_sampler.toggle_play(chop_track_index)
      end
    elsif [*(AbletonPush.drum_row_size() + AbletonPush.chop_sample_row_size())..(AbletonPush.pad_row_size() - AbletonPush.synth_row_size() - 1)].include? row
      sample_row = row - AbletonPush.drum_row_size() - AbletonPush.chop_sample_row_size()
      if @edit_modifier_pressed
        @sampler.edit(sample_row, column)
      else
        @sampler.arm_or_toggle_play(sample_row, column)
      end
    elsif [*(AbletonPush.pad_row_size() - AbletonPush.synth_row_size())..(AbletonPush.pad_row_size() - 1)].include? row
      synth_edit_index = row * 8 + column - (AbletonPush.pad_column_size() * (AbletonPush.pad_row_size() - AbletonPush.synth_row_size()))
      synth_track = @synthesizer.synth_tracks[synth_edit_index]
      if synth_track.bars == nil or @edit_modifier_pressed
        if synth_track.bars != nil
          set_recording_bar_power (Math::log(synth_track.bars) / Math::log(2)).to_i
        else
          @synthesizer.toggle_play(synth_edit_index)
        end
        @synthesizer.edit synth_edit_index
        switch_mode :SYNTH_MODE
      else
        @synthesizer.toggle_play synth_edit_index
      end
    end
  end

  def pad_off_callback(row, column, velocity)
    if not @@mode == :SESSION_MODE
      return
    end

    if [*AbletonPush.drum_row_size()..(AbletonPush.drum_row_size() + AbletonPush.chop_sample_row_size() - 1)].include? row
      if @chop_sampler.recording_chop() != nil
        @chop_sampler.end_record()
        switch_mode :CHOP_MODE
      end
    end
  end
  
  def control_callback(note, velocity)
    if velocity == 127
      if [*20..20 + @@recording_bar_options].include? note
        power = (note - 19) - 1
        set_recording_bar_power power
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
            @is_recording = false
            @sonic_pi.osc_send.call 'localhost', 4557, '/stop-recording', 'sonic-push'
            @push.color_note 86, NoteColorPalette.dim
            @sonic_pi.sleep.call 0.5
            @sonic_pi.osc_send.call 'localhost', 4557, '/save-recording', 'sonic-push', "#{@save_location}/sonic-push-#{Time.now.to_i}.wav"
          end
        end
      elsif note == 3
        @monitor_active = !@monitor_active
      end
    end
    if note == 49
      @edit_modifier_pressed = velocity == 127
    elsif note == 78
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
    @chop_sampler.set_recording_bar_power
    @synthesizer.set_recording_bar_power
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
  
  def switch_mode(mode)
    @@mode = mode
    clear_instrument_editing_menu()
    @push.color_note 3, NoteColorPalette.lit
    @push.color_note 9, NoteColorPalette.lit
    @push.color_note 44, NoteColorPalette.off
    @push.color_note 45, NoteColorPalette.off
    @push.color_note 46, NoteColorPalette.off
    @push.color_note 47, NoteColorPalette.off
    @push.color_note 49, NoteColorPalette.off
    
    case mode
    when :DRUM_MODE
      # Set active mode to true to prevent coloring playing pads
      @drum_machine.is_active_mode = true
      @push.clear
      @sonic_pi.sleep.call 0.1
      
      @sampler.is_active_mode = false
      # Set active mode to true to configure active mode
      @drum_machine.is_active_mode = true
      @push.color_note 51, NoteColorPalette.lit
    when :SESSION_MODE
      @push.clear
      @sonic_pi.sleep.call 0.1
      
      @drum_machine.is_active_mode = false
      print_editing_menu()
      @sampler.is_active_mode = true
      @push.color_note 51, NoteColorPalette.dim
      @push.color_note 49, NoteColorPalette.lit
    when :SYNTH_MODE
    when :CHOP_MODE
      @push.clear
      @sonic_pi.sleep.call 0.1

      @drum_machine.is_active_mode = false
      @sampler.is_active_mode = false
      @push.color_note 51, NoteColorPalette.lit
    end

    @synthesizer.mode_change()
    @chop_sampler.mode_change()
  end
  
  def print_editing_menu()
    @push.write_display(0, 3, "Global")
    @push.write_display(1, 3, "LPF #{@mixer.lpf}")
    @push.write_display(2, 3, "HPF #{@mixer.hpf}")
  end

  def clear_instrument_editing_menu()
    [*0..3].each do | row |
      [*1..2].each do | column |
        @push.clear_display_section(row, column)
      end
    end
  end
end
