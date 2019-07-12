require_relative 'color-pallete.rb'

class DrumMachine
  Drum = Struct.new(:sample, :color, :notes)
  DrumNote = Struct.new(:active, :volume)
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @color_off = Color.new(0, 0, 0)
    @mode = :DRUM_NOTE_MODE
    @current_drum_edit = 0
    
    @drums = [
      Drum.new(:drum_bass_hard, Color.new(0, 0, 255), Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_snare_hard, Color.new(0, 255, 0), Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_tom_lo_hard, Color.new(255, 0, 0), Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_tom_mid_hard, Color.new(0, 255, 255), Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_tom_hi_hard, Color.new(255, 255, 0), Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_cowbell, Color.new(255, 0, 255), Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_cymbal_closed, Color.new(128, 255, 128), Array.new(8) { |i| DrumNote.new(false, 4) }),
      Drum.new(:drum_cymbal_open, Color.new(128, 128, 255), Array.new(8) { |i| DrumNote.new(false, 4) })
    ]
    
    @push.clear
    
    @sonic_pi.live_loop.call :drum do
      @sonic_pi.use_bpm.call 95
      @sonic_pi.sync.call :master
      @sonic_pi.tick.call
      
      @drums.each do | drum |
        @sonic_pi.sample.call drum.sample, amp: drum.notes.look.volume / 8.0 if drum.notes.look.active == true
      end
      
      @push.tick @sonic_pi.look.call
      @sonic_pi.sleep.call 0.25
    end
    
    @push.register_note_callback(method(:note_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  def switch_mode(mode)
    case mode
    when :DRUM_NOTE_MODE
      @push.set_show_tick true
      @push.clear
      @drums.each_with_index do | drum, row |
        drum.notes.each_with_index do | note, column |
          @push.color_row_column row, column, note.active == false ? @color_off : drum.color
        end
      end
      
    when :DRUM_EDIT_MODE
      @push.set_show_tick false
      @push.clear
      drum = @drums[@current_drum_edit]
      drum.notes.each_with_index do | note, index |
        8.times do | volume |
          @push.color_row_column volume, index, volume <= note.volume ? drum.color : @color_off
        end
      end
    end
  end
  
  def note_callback(row, column, velocity)
    case @mode
    when :DRUM_NOTE_MODE
      drum = @drums[row]
      drum.notes[column].active = drum.notes[column].active == false ? true : false
      @push.color_row_column row, column, drum.notes[column].active == false ? @color_off : drum.color
    when :DRUM_EDIT_MODE
      drum = @drums[@current_drum_edit]
      drum.notes[column].volume = row + 1
      8.times do | volume |
        @push.color_row_column volume, column, volume <= row ? drum.color : @color_off
      end
    end
  end
  
  def control_callback(note, velocity)
    if note == 14 # tempo
      bpm += velocity == 1 ? 1 : -1
    elsif [*36..43].include? note and velocity == 127
      drum_edit = note - 36
      if (@current_drum_edit == drum_edit and @mode == :DRUM_EDIT_MODE)
        @mode = :DRUM_NOTE_MODE
        switch_mode(:DRUM_NOTE_MODE)
      else
        @mode = :DRUM_EDIT_MODE
        @current_drum_edit = drum_edit
        switch_mode(:DRUM_EDIT_MODE)
      end
    end
  end
end
