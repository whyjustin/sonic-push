require_relative 'clock.rb'
require_relative 'color-pallete.rb'

class DrumMachine
  Drum = Struct.new(:sample, :color, :notes)
  DrumNote = Struct.new(:active, :volume)
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @mode = :DRUM_NOTE_MODE
    @current_drum_edit = 0
    
    @drums = [
      Drum.new(:drum_bass_hard, PadColorPallete.blue, Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_snare_hard, PadColorPallete.green, Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_tom_lo_hard, PadColorPallete.red, Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_tom_mid_hard, PadColorPallete.teal, Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_tom_hi_hard, PadColorPallete.yellow, Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_cowbell, PadColorPallete.magenta, Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_cymbal_closed, PadColorPallete.lime, Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_cymbal_open, PadColorPallete.violet, Array.new(8) { |i| DrumNote.new(false, 4) })
    ]
    
    @is_active_mode = false
    
    @sonic_pi.live_loop.call :drum do
      @sonic_pi.use_bpm.call Clock.bpm
      @sonic_pi.sync.call :master_cue
      
      8.times do | step |
        @drums.each do | drum |
          @sonic_pi.sample.call drum.sample, amp: drum.notes[step].volume / 8.0 if drum.notes[step].active == true
        end
        
        @push.tick step
        @sonic_pi.sleep.call 0.5
      end
    end
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  def is_active_mode=is_active_mode
    if is_active_mode
      switch_mode(:DRUM_NOTE_MODE)
    else
      @push.show_tick = false
    end
    @is_active_mode = is_active_mode
  end
  
  def switch_mode(mode)
    case mode
    when :DRUM_NOTE_MODE
      @push.show_tick = true
      @push.clear
      @sonic_pi.sleep.call 0.5
      @drums.each_with_index do | drum, row |
        drum.notes.each_with_index do | note, column |
          @push.color_row_column row, column, note.active == false ? PadColorPallete.black : drum.color
        end
      end
      
    when :DRUM_EDIT_MODE
      @push.show_tick = false
      @push.clear
      @sonic_pi.sleep.call 0.5
      drum = @drums[@current_drum_edit]
      drum.notes.each_with_index do | note, index |
        8.times do | volume |
          @push.color_row_column volume, index, volume <= note.volume ? drum.color : PadColorPallete.black
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
      @push.color_row_column row, column, drum.notes[column].active == false ? PadColorPallete.black : drum.color
    when :DRUM_EDIT_MODE
      drum = @drums[@current_drum_edit]
      drum.notes[column].volume = row + 1
      8.times do | volume |
        @push.color_row_column volume, column, volume <= row ? drum.color : PadColorPallete.black
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
