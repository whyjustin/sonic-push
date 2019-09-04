require_relative 'session-machine.rb'
require_relative 'ableton-push.rb'
require_relative 'color-palette.rb'

# Synthesizer is too large to load in the Sonic Pi editor
# Extracted some methods to reduce buffer size
class SynthesizerHelper  
  SynthTrack = Struct.new(:instrument_index, :is_playing, :bars, :row, :column, :steps)
  Scale = Struct.new(:name, :base_note, :notes)

  @@scales = []

  def self.scales
    return @@scales
  end

  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push

    @@scales.push(Scale.new("Cmaj", 0, [0,2,4,5,7,9,11]))
    @@scales.push(Scale.new("Emaj", 4, [1,3,4,6,8,9,11]))
    @@scales.push(Scale.new("Emin", 4, [0,2,4,6,7,9,11]))
    @@scales.push(Scale.new("Amaj", 9, [1,2,4,6,8,9,11]))
    @@scales.push(Scale.new("Amin", 9, [0,2,4,5,7,9,11]))
  end
  
  def get_viewing_note_step(synth, step, viewing_bar)
    return synth.steps[viewing_bar * Synthesizer.steps_per_bar + step]
  end

  def auto_color_synth_track(synth_track)
    if synth_track.bars != nil
      if synth_track.is_playing
        color_synth_track synth_track, PadColorPalette.green
      else
        color_synth_track synth_track, PadColorPalette.blue
      end
    else
      color_synth_track synth_track, PadColorPalette.black
    end
  end
  
  def color_synth_track(synth_track, color)
    if SessionMachine.mode != :SESSION_MODE
      return
    end
    
    @push.color_row_column synth_track.row, synth_track.column, color
  end
end
