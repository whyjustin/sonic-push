require_relative 'ableton-push.rb'

# DrumMachine is too large to load in the Sonic Pi editor
# Extracted some methods to reduce buffer size
class DrumMachineHelper
  DrumTrack = Struct.new(:kit_index, :is_playing, :bars, :swing, :reverb_mix, :reverb_control, :row, :column, :drums)
  Drum = Struct.new(:color, :notes)
  DrumNote = Struct.new(:active, :volume)

  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
  end

  def get_default_kit()
    return [
      :drum_bass_hard,
      :drum_snare_hard,
      :drum_tom_lo_hard,
      :drum_tom_mid_hard,
      :drum_tom_hi_hard,
      :drum_cowbell,
      :drum_cymbal_closed,
      :drum_cymbal_open
    ]
  end

  def build_drum_tracks()
    drum_tracks = []
    AbletonPush.drum_row_size().times do | i |
      AbletonPush.pad_column_size().times do | j |
        drum_tracks.push(DrumTrack.new(0, false, nil, 0, 0.0, nil, i, j, [
                                          Drum.new(PadColorPalette.blue, []),
                                          Drum.new(PadColorPalette.green, []),
                                          Drum.new(PadColorPalette.red, []),
                                          Drum.new(PadColorPalette.teal, []),
                                          Drum.new(PadColorPalette.yellow, []),
                                          Drum.new(PadColorPalette.magenta, []),
                                          Drum.new(PadColorPalette.lime, []),
                                          Drum.new(PadColorPalette.violet, [])
        ]))
      end
    end
    return drum_tracks
  end

  def auto_color_drum_track(is_active_mode, drum_track)
    if drum_track.bars != nil
      if drum_track.is_playing
        color_drum_track is_active_mode, drum_track, PadColorPalette.green
      else
        color_drum_track is_active_mode, drum_track, PadColorPalette.blue
      end
    else
      color_drum_track is_active_mode, drum_track, PadColorPalette.black
    end
  end
  
  def color_drum_track(is_active_mode, drum_track, color)
    if is_active_mode
      return
    end
    
    @push.color_row_column drum_track.row, drum_track.column, color
  end
  
  def print_editing_menu(is_active_mode, editing_drums)
    if not is_active_mode
      return
    end
    
    if editing_drums != nil
      clear_editing_menu()
      @sonic_pi.sleep.call 0.1
      @push.write_display(0, 1, "Drum")
      @push.write_display(1, 1, "Swing #{editing_drums.swing}")
      @push.write_display(2, 1, "Reverb #{editing_drums.reverb_mix}")
      @push.write_display(3, 1, "Kit #{editing_drums.kit_index}")
    end
  end

  def clear_editing_menu()
    @push.clear_display_section(0, 1)
    @push.clear_display_section(1, 1)
    @push.clear_display_section(2, 1)
    @push.clear_display_section(3, 1)
  end
end
