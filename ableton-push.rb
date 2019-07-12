require_relative 'color-pallete.rb'

class AbletonPush
  def initialize(sonic_pi)
    @sonic_pi = sonic_pi
    @sonic_pi.midi_sysex.call 240,71,127,21,98,0,1,1,247
    clear_display()
    write_display(0, 0, "Sonic Push")
    
    @color_off = Color.new(0, 0, 0)
    @color_grid = Array.new(8) { |i| Array.new(8) { |j| @color_off } }
    @old_color_grid = Array.new(8) { |i| Array.new(8) { |j| @color_off } }
    
    @note_callbacks = []
    @control_callbacks = []
    
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
        @note_callbacks.each do | callback |
          callback.call (note - 36) / 8, (note - 36) % 8, velocity
        end
      end
    end
    
    @sonic_pi.in_thread.call do
      @sonic_pi.loop.call do
        @sonic_pi.use_real_time.call
        note, velocity = @sonic_pi.sync.call '/midi/ableton_push_user_port/1/1/control_change'
        @control_callbacks.each do | callback |
          callback.call note, velocity
        end
      end
    end
  end
  
  def color_row_column(row, column, color)
    @color_grid[row][column] = color
    color_pad row * 8 + column, color
  end
  
  def color_second_strip(column, color)
    pad = column + 102
    @sonic_pi.midi_cc.call pad, color
  end
  
  def color_pad(pad, color)
    @sonic_pi.midi_sysex.call 240,71,127,21,4,0,8,pad,0,color.red/16,color.red%16,color.green/16,color.green%16,color.blue/16,color.blue%16,247
  end
  
  def tick(tick_count)
    if @show_tick
      tick_count = tick_count % 8
      @color_grid.each do | row |
        8.times do | pad |
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
    @note_callbacks.push(callback)
  end
  
  def register_control_callback(callback)
    @control_callbacks.push(callback)
  end
  
  def clear
    @color_grid.each do | row |
      row.each_with_index do | column, index |
        row[index] = @color_off
      end
    end
  end
  
  def clear_second_strip
    8.times do | i |
      color_second_strip i, SecondStripColorPallete.black
    end
  end
  
  def set_show_tick(show_tick)
    @show_tick = show_tick
  end
  
  def clear_display()
    4.times.each do | line |
      @sonic_pi.midi_sysex.call 240, 71, 127, 21, 28 + line, 0, 0, 247, on: false
    end
  end
  
  def write_display(row, column, string)
    string.split('').each_with_index do | char, index |
      @sonic_pi.midi_sysex.call 240, 71, 127, 21, 24 + row, 0, 2, column + index, char.ord, 247
    end
  end
end
