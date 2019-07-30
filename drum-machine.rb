require_relative 'clock.rb'
require_relative 'color-palette.rb'
require_relative 'session-machine.rb'

class DrumMachine
  Drum = Struct.new(:sample, :color, :notes)
  DrumNote = Struct.new(:active, :volume)
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @mode = :DRUM_NOTE_MODE
    @current_drum_edit = 0
    
    @drum_tracks = []
    16.times do | i |
      @drum_tracks.push([
                          Drum.new(:drum_bass_hard, PadColorPalette.blue, nil),
                          Drum.new(:drum_snare_hard, PadColorPalette.green, nil),
                          Drum.new(:drum_tom_lo_hard, PadColorPalette.red, nil),
                          Drum.new(:drum_tom_mid_hard, PadColorPalette.teal, nil),
                          Drum.new(:drum_tom_hi_hard, PadColorPalette.yellow, nil),
                          Drum.new(:drum_cowbell, PadColorPalette.magenta, nil),
                          Drum.new(:drum_cymbal_closed, PadColorPalette.lime, nil),
                          Drum.new(:drum_cymbal_open, PadColorPalette.violet, nil)
      ])
    end
    
    @is_active_mode = false
    
    @sonic_pi.live_loop.call :drum do
      @sonic_pi.use_bpm.call Clock.bpm
      @sonic_pi.sync.call :master_cue
      
      if @drums != nil and @drums[0].notes != nil
        get_drum_steps().times do | step |
          @drums.each do | drum |
            @sonic_pi.sample.call drum.sample, amp: drum.notes[step].volume / 8.0 if drum.notes[step].active == true
          end
          
          @sonic_pi.sleep.call 0.5
        end
      end
    end
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  def load(track_number)
    drums = @drum_tracks[track_number]
    if drums[0].notes == nil
      drums.each do | drum |
        drum.notes = Array.new(get_drum_steps()) { |i| DrumNote.new(false, 4) }
      end
    end
    @drums = drums
  end
  
  def get_drum_steps
    return SessionMachine.recording_steps * 2
  end
  
  def is_active_mode=is_active_mode
    if is_active_mode
      switch_mode(:DRUM_NOTE_MODE)
    end
    @is_active_mode = is_active_mode
  end
  
  def switch_mode(mode)
    case mode
    when :DRUM_NOTE_MODE
      @push.clear
      @sonic_pi.sleep.call 0.5
      @drums.each_with_index do | drum, row |
        drum.notes.each_with_index do | note, column |
          @push.color_row_column row, column, note.active == false ? PadColorPalette.black : drum.color
        end
      end
      
    when :DRUM_EDIT_MODE
      @push.clear
      @sonic_pi.sleep.call 0.5
      drum = @drums[@current_drum_edit]
      drum.notes.each_with_index do | note, index |
        8.times do | volume |
          @push.color_row_column volume, index, volume <= note.volume ? drum.color : PadColorPalette.black
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
      drum = @drums[row]
      drum.notes[column].active = drum.notes[column].active == false ? true : false
      @push.color_row_column row, column, drum.notes[column].active == false ? PadColorPalette.black : drum.color
    when :DRUM_EDIT_MODE
      drum = @drums[@current_drum_edit]
      drum.notes[column].volume = row + 1
      8.times do | volume |
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
        @mode = :DRUM_NOTE_MODE
        switch_mode :DRUM_NOTE_MODE
      else
        @mode = :DRUM_EDIT_MODE
        @current_drum_edit = drum_edit
        switch_mode :DRUM_EDIT_MODE
      end
    end
  end
end
