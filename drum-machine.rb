require_relative 'clock.rb'
require_relative 'color-palette.rb'
require_relative 'session-machine.rb'
require_relative 'helper.rb'

class DrumMachine
  DrumTrack = Struct.new(:is_playing, :bars, :swing, :reverb_mix, :reverb_control, :row, :column, :drums)
  Drum = Struct.new(:sample, :color, :notes)
  DrumNote = Struct.new(:active, :volume)
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @mode = :DRUM_NOTE_MODE
    @current_drum_edit = 0
    
    @drum_steps_per_bar = SessionMachine.steps_per_bar * 2
    
    @kit = :default_kit
    
    @drum_tracks = []
    2.times do | i |
      8.times do | j |
        @drum_tracks.push(DrumTrack.new(false, nil, 0, 0.0, nil, i, j, [
                                          Drum.new(:drum_bass_hard, PadColorPalette.blue, []),
                                          Drum.new(:drum_snare_hard, PadColorPalette.green, []),
                                          Drum.new(:drum_tom_lo_hard, PadColorPalette.red, []),
                                          Drum.new(:drum_tom_mid_hard, PadColorPalette.teal, []),
                                          Drum.new(:drum_tom_hi_hard, PadColorPalette.yellow, []),
                                          Drum.new(:drum_cowbell, PadColorPalette.magenta, []),
                                          Drum.new(:drum_cymbal_closed, PadColorPalette.lime, []),
                                          Drum.new(:drum_cymbal_open, PadColorPalette.violet, [])
        ]))
      end
    end
    
    @is_active_mode = false
    
    steps = [*0..(@drum_steps_per_bar - 1)].ring
    current_bar = 0
    @drum_tracks.each do | drum_track |
      @sonic_pi.with_fx.call :reverb do | r |
        drum_track.reverb_control = r
        @sonic_pi.live_loop.call "drum_machine_#{drum_track.row}_#{drum_track.column}" do
          step = steps.tick
          # Sync every bar to prevent drift
          if step == 0
            @sonic_pi.use_bpm.call Clock.bpm
            @sonic_pi.sync.call :master_cue
            
            current_bar = SessionMachine.current_bar
          end
          @sonic_pi.with_swing.call drum_track.swing, pulse: 2 do
            if drum_track.bars != nil and drum_track.is_playing
              color_drum_track drum_track, PadColorPalette.green
              bar_step = current_bar % drum_track.bars * @drum_steps_per_bar + step
              
              retrigger = SessionMachine.retrigger
              if retrigger != nil and (@editing_drums == nil or drum_track == @editing_drums)
                bar_step = bar_step % retrigger
              end

              drum_track.drums.each_with_index do | drum, index |
                if @kit != :default_kit
                  @sonic_pi.sample.call @kit, index, amp: drum.notes[bar_step].volume / 8.0 if drum.notes[bar_step].active == true
                else
                  @sonic_pi.sample.call drum.sample, amp: drum.notes[bar_step].volume / 8.0 if drum.notes[bar_step].active == true
                end
              end
            else
              color_drum_track drum_track, PadColorPalette.black
            end
          end
          @sonic_pi.sleep.call 0.5
        end
      end

      #Throttle Initialization
      @sonic_pi.sleep.call 0.1
    end
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  def drum_tracks()
    return @drum_tracks
  end
  
  def toggle_play(track_number)
    drum_track = @drum_tracks[track_number]
    drum_track.is_playing = !drum_track.is_playing
    color_drum_track drum_track, PadColorPalette.grey
  end
  
  def edit(track_number)
    @editing_drums = @drum_tracks[track_number]
    set_recording_bar_power
  end
  
  def load_kit(kit)
    @kit = kit
  end
  
  def set_recording_bar_power()
    if @editing_drums != nil
      i = 0
      until i > SessionMachine.recording_bars - 1
        bar_step = i * @drum_steps_per_bar
        if @editing_drums.drums[0].notes.length <= bar_step
          @editing_drums.drums.each do | drum |
            @drum_steps_per_bar.times do | j |
              step = bar_step + j
              last_bar_step = step - @drum_steps_per_bar
              if last_bar_step >= 0 and drum.notes.length >= last_bar_step
                drum.notes.push(drum.notes[last_bar_step].dup)
              else
                drum.notes.push(DrumNote.new(false, 4))
              end
            end
          end
        end
        i = i + 1
      end
      @editing_drums.bars = SessionMachine.recording_bars
    end
  end
  
  def set_viewing_bar()
    switch_mode @mode
  end
  
  def get_drum_steps
    return SessionMachine.recording_steps * 2
  end
  
  def is_active_mode=is_active_mode
    @is_active_mode = is_active_mode
    if is_active_mode
      switch_mode(:DRUM_NOTE_MODE)
      print_editing_menu()
    else
      @editing_drums = nil
      @drum_tracks.each do | drum_track |
        if drum_track.bars != nil and drum_track.is_playing
          color_drum_track drum_track, PadColorPalette.green
        else
          color_drum_track drum_track, PadColorPalette.black
        end
      end
    end
  end
  
  def switch_mode(mode)
    @mode = mode
    case @mode
    when :DRUM_NOTE_MODE
      @push.clear
      @sonic_pi.sleep.call 0.1
      @editing_drums.drums.each_with_index do | drum, row |
        @drum_steps_per_bar.times do | step |
          note = get_viewing_note(drum, step)
          @push.color_row_column row, step, note.active == false ? PadColorPalette.black : drum.color
        end
      end
    when :DRUM_EDIT_MODE
      @push.clear
      @sonic_pi.sleep.call 0.1
      drum = @editing_drums.drums[@current_drum_edit]
      @drum_steps_per_bar.times do | step |
        note = get_viewing_note(drum, step)
        8.times do | volume |
          @push.color_row_column volume, step, volume <= note.volume ? drum.color : PadColorPalette.black
        end
      end
    end
  end
  
  def pad_callback(row, column, velocity)
    if not @is_active_mode
      return
    end
    
    case @mode
    when :DRUM_NOTE_MODE
      drum = @editing_drums.drums[row]
      viewing_drum = get_viewing_note(drum, column)
      viewing_drum.active = viewing_drum.active == false ? true : false
      @push.color_row_column row, column, viewing_drum.active == false ? PadColorPalette.black : drum.color
    when :DRUM_EDIT_MODE
      drum = @editing_drums.drums[@current_drum_edit]
      viewing_drum = get_viewing_note(drum, column)
      viewing_drum.volume = row + 1
      @drum_steps_per_bar.times do | volume |
        @push.color_row_column volume, column, volume <= row ? drum.color : PadColorPalette.black
      end
    end
  end
  
  def control_callback(note, velocity)
    if not @is_active_mode
      return
    end
    
    if [*36..43].include? note and velocity == 127
      drum_edit = note - 36
      if (@current_drum_edit == drum_edit and @mode == :DRUM_EDIT_MODE)
        switch_mode :DRUM_NOTE_MODE
      else
        @current_drum_edit = drum_edit
        switch_mode :DRUM_EDIT_MODE
      end
    elsif note == 71
      if @editing_drums != nil
        @editing_drums.swing = Helper.within(@editing_drums.swing + (velocity == 1 ? 0.01 : -0.01), -0.5, 0.5).round(2)
        print_editing_menu()
      end
    elsif note == 72
      if @editing_drums != nil
        @editing_drums.reverb_mix = Helper.within(@editing_drums.reverb_mix + (velocity == 1 ? 0.01 : -0.01), 0.0, 1.0).round(2)
        @sonic_pi.control.call @editing_drums.reverb_control, mix: @editing_drums.reverb_mix
        print_editing_menu()
      end
    end
  end
  
  def get_viewing_note(drum, column)
    return drum.notes[SessionMachine.viewing_bar * @drum_steps_per_bar + column]
  end
  
  def color_drum_track(drum_track, color)
    if @is_active_mode
      return
    end
    
    @push.color_row_column drum_track.row, drum_track.column, color
  end
  
  def print_editing_menu()
    if not @is_active_mode
      return
    end
    
    if @editing_drums != nil
      clear_editing_menu()
      @sonic_pi.sleep.call 0.1
      @push.write_display(0, 1, "Drum")
      @push.write_display(1, 1, "Swing #{@editing_drums.swing}")
      @push.write_display(2, 1, "Reverb #{@editing_drums.reverb_mix}")
    end
  end

  def clear_editing_menu()
    @push.clear_display_section(0, 1)
    @push.clear_display_section(1, 1)
    @push.clear_display_section(2, 1)
  end
end
