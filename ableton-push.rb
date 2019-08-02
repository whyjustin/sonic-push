require_relative 'color-palette.rb'

class AbletonPush
  def self.pad_column_size()
    return 8
  end

  def self.drum_row_size()
    return 2
  end

  def initialize(sonic_pi)
    @sonic_pi = sonic_pi
    
    @color_grid = Array.new(8) { |i| Array.new(8) { |j| PadColorPalette.black } }
    @first_strip = Array.new(8) { |i| Array.new(8) { |j| FirstStripColorPalette.black } }
    @second_strip = Array.new(8) { |i| Array.new(8) { |j| SecondStripColorPalette.black } }

    clear()
    clear_first_strip()
    clear_second_strip()
    [*0..3].each do | row |
      [*1..2].each do | column |
        clear_display_section(row, column)
      end
    end
    write_display(0, 0, "Sonic Push")
    
    @pad_callbacks = []
    @control_callbacks = []
    @note_callbacks = []
    @pitch_callbacks = []
    
    @sonic_pi.in_thread.call do
      @sonic_pi.loop.call do
        @sonic_pi.use_real_time.call
        note, velocity = @sonic_pi.sync.call '/midi/ableton_push_user_port/1/1/note_on'
        if [*36..99].include? note
          @pad_callbacks.each do | callback |
            callback.call (note - 36) / 8, (note - 36) % 8, velocity
          end
        else
          @note_callbacks.each do | callback |
            callback.call note, velocity
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

    @sonic_pi.in_thread.call do
      @sonic_pi.loop.call do
        @sonic_pi.use_real_time.call
        pitch = @sonic_pi.sync.call '/midi/ableton_push_user_port/1/1/pitch_bend'
        @pitch_callbacks.each do | callback |
          callback.call pitch[0]
        end
      end
    end
  end
  
  def color_row_column(row, column, color)
    color_pad row * 8 + column, color, false
  end

  def force_color_row_column(row, column, color)
    color_pad row * 8 + column, color, true
  end
  
  def color_first_strip(column, color)
    if @second_strip[column] != color
      @second_strip[column] = color
      pad = column + 20
      @sonic_pi.midi_cc.call pad, color
    end
  end

  def color_second_strip(column, color)
    if @first_strip[column] != color
      @first_strip[column] = color
      pad = column + 102
      @sonic_pi.midi_cc.call pad, color
    end
  end

  def color_note(note, color)
    @sonic_pi.midi_cc.call note, color
  end
  
  def color_pad(pad, color, force)
    if @color_grid[pad / 8][pad % 8] != color || force
      @color_grid[pad / 8][pad % 8] = color
      @sonic_pi.midi_sysex.call 240,71,127,21,4,0,8,pad,0,color.red/16,color.red%16,color.green/16,color.green%16,color.blue/16,color.blue%16,247
    end
  end
  
  def register_pad_callback(callback)
    @pad_callbacks.push(callback)
  end
  
  def register_control_callback(callback)
    @control_callbacks.push(callback)
  end

  def register_note_callback(callback)
    @note_callbacks.push(callback)
  end

  def register_pitch_callback(callback)
    @pitch_callbacks.push(callback)
  end
  
  def clear
    @color_grid.each_with_index do | row, row_index |
      row.each_with_index do | column, column_index |
        force_color_row_column row_index, column_index, PadColorPalette.black
      end
    end
  end
  
  def clear_first_strip
    8.times do | i |
      color_second_strip i, FirstStripColorPalette.black
    end
  end

  def clear_second_strip
    8.times do | i |
      color_second_strip i, SecondStripColorPalette.black
    end
  end
  
  def clear_display()
    4.times.each do | row |
      4.times.each do | column |
        clear_display_section row, column
      end
    end
  end

  def clear_display_section(row, display_column)
    #@sonic_pi.midi_sysex.call 240, 71, 127, 21, 28 + row, 0, 0, 247
    write_display row, display_column, ' ' * 17
  end
  
  def write_display(row, display_column, string)
    string.split('').each_with_index do | char, index |
      @sonic_pi.midi_sysex.call 240, 71, 127, 21, 24 + row, 0, 2, display_column * 17 + index, char.ord, 247, on: true
    end
  end
end
