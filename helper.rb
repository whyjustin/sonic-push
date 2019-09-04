class Helper
  def self.within(number, min, max)
    return [max, [min, number].max].min
  end

  def self.auto_color_track(push, track)
    if track.bars != nil
      if track.is_playing
        color_track push, track, PadColorPalette.green
      else
        color_track push, track, PadColorPalette.blue
      end
    else
      color_track push, track, PadColorPalette.black
    end
  end

  def self.color_track(push, track, color)
    if SessionMachine.mode != :SESSION_MODE
      return
    end

    push.color_row_column track.row, track.column, color
  end
end
