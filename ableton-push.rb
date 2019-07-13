require_relative 'color-pallete.rb'

class AbletonPush
  def initialize(sonic_pi)
    @sonic_pi = sonic_pi
    clear_display()
    write_display(0, 0, "Sonic Push")
    
    @color_grid = Array.new(8) { |i| Array.new(8) { |j| PadColorPallete.black } }
    @old_color_grid = Array.new(8) { |i| Array.new(8) { |j| PadColorPallete.black } }
    
    @note_callbacks = []
    @control_callbacks = []
    
    @show_tick = true
    
    @sonic_pi.in_thread.call do
      @sonic_pi.loop.call do
        @sonic_pi.use_real_time.call
        note, velocity = @sonic_pi.sync.call '/midi/ableton_push_user_port/1/1/note_on'
        if [*36..99].include? note
          @note_callbacks.each do | callback |
            callback.call (note - 36) / 8, (note - 36) % 8, velocity
          end
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
    color_pad row * 8 + column, color
  end
  
  def color_second_strip(column, color)
    pad = column + 102
    @sonic_pi.midi_cc.call pad, color
  end
  
  def color_pad(pad, color)
    @color_grid[pad / 8][pad % 8] = color
    @sonic_pi.midi_sysex.call 240,71,127,21,4,0,8,pad,0,color.red/16,color.red%16,color.green/16,color.green%16,color.blue/16,color.blue%16,247
  end
  
  def tick(tick_count)
    if @show_tick
      tick_count = tick_count % 8
      @color_grid.each_with_index do | row, row_index |
        8.times do | column_index |
          if row[column_index] == PadColorPallete.grey
            color_row_column row_index, column_index, PadColorPallete.black
          end
        end
        
        if row[tick_count] == PadColorPallete.black
          color_row_column row_index, tick_count, PadColorPallete.grey
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
    @color_grid.each_with_index do | row, row_index |
      row.each_with_index do | column, column_index |
        color_row_column row_index, column_index, PadColorPallete.black
      end
    end
  end
  
  def clear_second_strip
    8.times do | i |
      color_second_strip i, SecondStripColorPallete.black
    end
  end
  
  def show_tick=show_tick
    @show_tick = show_tick
  end
  
  def clear_display()
    4.times.each do | row |
      4.times.each do | column |
        clear_display_section row, column
      end
    end
  end

  def clear_display_section(row, display_column)
    write_display row, display_column * 17, ' ' * 17
  end
  
  def write_display(row, column, string)
    string.split('').each_with_index do | char, index |
      @sonic_pi.midi_sysex.call 240, 71, 127, 21, 24 + row, 0, 2, column + index, char.ord, 247, on: true
    end
  end
end
