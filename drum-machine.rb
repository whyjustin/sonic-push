require_relative 'clock.rb'
require_relative 'color-palette.rb'
require_relative 'session-machine.rb'

class DrumMachine
  DrumTrack = Struct.new(:is_playing, :bars, :row, :column, :drums)
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
        @drum_tracks.push(DrumTrack.new(false, nil, i, j, [
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
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  def play(current_bar)
    @drum_tracks.each do | drum_track |
      if drum_track.bars != nil and current_bar % drum_track.bars == 0
        if drum_track.is_playing
          color_drum_track drum_track, PadColorPalette.green
          @sonic_pi.in_thread.call do
            (@drum_steps_per_bar * drum_track.bars).times do | step |
              bar_step = current_bar % drum_track.bars * @drum_steps_per_bar + step
              drum_track.drums.each_with_index do | drum, index |
                if @kit != :default_kit
                  @sonic_pi.sample.call @kit, index, amp: drum.notes[bar_step].volume / 8.0 if drum.notes[bar_step].active == true
                else
                  @sonic_pi.sample.call drum.sample, amp: drum.notes[bar_step].volume / 8.0 if drum.notes[bar_step].active == true
                end
              end
              
              @sonic_pi.sleep.call 0.5
            end
          end
        else
          color_drum_track drum_track, PadColorPalette.black
        end
      end
    end
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
    else
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
          @sonic_pi.puts.call "#{step} #{SessionMachine.viewing_bar} #{drum.notes.length}"
          note = get_viewing_note(drum, step)
          @sonic_pi.puts.call "#{note} #{SessionMachine.recording_bars}"
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
end
