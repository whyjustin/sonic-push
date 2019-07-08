Color = Struct.new(:red, :green, :blue)

SonicPiWrapper = Struct.new(:in_thread, :loop, :live_loop, :use_bpm, :sleep, :sync, :use_real_time, :tick, :look, :midi_sysex, :sample)
sonic_pi = SonicPiWrapper.new(method(:in_thread), method(:loop), method(:live_loop), method(:use_bpm), method(:sleep), method(:sync), method(:use_real_time), method(:tick), method(:look), method(:midi_sysex), method(:sample))

class AbletonPush
  def initialize(sonic_pi)
    @sonic_pi = sonic_pi
    
    @color_off = Color.new(0, 0, 0)
    @color_grid = Array.new(8) { |i| Array.new(8) { |j| @color_off } }
    @old_color_grid = Array.new(8) { |i| Array.new(8) { |j| @color_off } }
    
    @note_callback = nil
    @control_callback = nil
    
    @show_tick = true
    
    @sonic_pi.in_thread.call do
      @sonic_pi.loop.call do
        @sonic_pi.use_bpm.call 480
        @color_grid.each_with_index do | row, column_index |
          row.each_with_index do | color, row_index|
            if color != @old_color_grid[column_index][row_index]
              color_pad column_index*8 + row_index, color
              @old_color_grid[column_index][row_index] = color
            end
          end
        end
        @sonic_pi.sleep.call 0.5
      end
    end
    
    @sonic_pi.in_thread.call do
      @sonic_pi.loop.call do
        @sonic_pi.use_real_time.call
        note, velocity = @sonic_pi.sync.call '/midi/ableton_push_user_port/1/1/note_on'
        if @note_callback != nil
          @note_callback.call (note - 36) / 8, (note - 36) % 8, velocity
        end
      end
    end
    
    @sonic_pi.in_thread.call do
      @sonic_pi.loop.call do
        @sonic_pi.use_real_time.call
        note, velocity = @sonic_pi.sync.call '/midi/ableton_push_user_port/1/1/control_change'
        if @control_callback != nil
          @control_callback.call note, velocity
        end
      end
    end
  end
  
  def set_color(row, column, color)
    @color_grid[row][column] = color
    color_pad row * 8 + column, color
  end
  
  def color_pad(pad, color)
    @sonic_pi.midi_sysex.call 240,71,127,21,4,0,8,pad,0,color.red/16,color.red%16,color.green/16,color.green%16,color.blue/16,color.blue%16,247
  end
  
  def tick(tick_count)
    if @show_tick
      tick_count = tick_count % 8
      @color_grid.each do | row |
        [*0..7].each do | pad |
          if row[pad] == Color.new(100, 100, 100)
            row[pad] = @color_off
          end
        end
        
        if row[tick_count] == @color_off #.red == 0 and row[tick_count].blue == 0 and row[tick_count].green == 0 #
          row[tick_count] = Color.new(100, 100, 100)
        end
      end
    end
  end
  
  def register_note_callback(callback)
    @note_callback = callback
  end
  
  def register_control_callback(callback)
    @control_callback = callback
  end
  
  def clear
    @color_grid.each do | row |
      row.each_with_index do | column, index |
        row[index] = @color_off
      end
    end
  end
  
  def set_show_tick(show_tick)
    @show_tick = show_tick
  end
end

color_off = Color.new(0, 0, 0)
push = AbletonPush.new(sonic_pi)

class DrumMachine
  Drum = Struct.new(:sample, :color, :notes)
  DrumNote = Struct.new(:active, :volume)
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @drums = [
      Drum.new(:drum_bass_hard, Color.new(0, 0, 255), Array.new(8) { |i| DrumNote.new(false) }),
      Drum.new(:drum_snare_hard, Color.new(0, 255, 0), Array.new(8) { |i| DrumNote.new(false) }),
      Drum.new(:drum_tom_lo_hard, Color.new(255, 0, 0), Array.new(8) { |i| DrumNote.new(false) }),
      Drum.new(:drum_tom_mid_hard, Color.new(0, 255, 255), Array.new(8) { |i| DrumNote.new(false) }),
      Drum.new(:drum_tom_hi_hard, Color.new(255, 255, 0), Array.new(8) { |i| DrumNote.new(false) }),
      Drum.new(:drum_cowbell, Color.new(255, 0, 255), Array.new(8) { |i| DrumNote.new(false) }),
      Drum.new(:drum_cymbal_closed, Color.new(128, 255, 128), Array.new(8) { |i| DrumNote.new(false) }),
      Drum.new(:drum_cymbal_open, Color.new(128, 128, 255), Array.new(8) { |i| DrumNote.new(false) })
    ]
    
    @sonic_pi.live_loop.call :drum do
      @sonic_pi.use_bpm.call 95
      @sonic_pi.sync.call :master
      @sonic_pi.tick.call
      
      @drums.each do | drum |
        @sonic_pi.sample.call drum.sample if drum.notes.look.active == true
      end
      
      @push.tick @sonic_pi.look.call
      @sonic_pi.sleep.call 0.25
    end
    
    @push.register_note_callback(method(:note_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  
  def note_callback(row, column, velocity)
    drum = @drums[row]
    drum.notes[column].active = drum.notes[column].active == false ? true : false
    @push.set_color row, column, drum.notes[column].active == false ? Color.new(0, 0, 0) : drum.color
  end
  
  def control_callback(note, velocity)
    if note == 14 # tempo
      bpm += velocity == 1 ? 1 : -1
    elsif note == 36
      @push.set_show_tick false
      @push.clear
    end
  end
end

drum_machine = DrumMachine.new(sonic_pi, push)

bpm = 95
use_bpm bpm

live_loop :master do
  use_bpm bpm
  sleep 0.125
end
