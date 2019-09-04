require_relative 'session-machine.rb'
require_relative 'color-palette.rb'

# Sampler is too large to load in the Sonic Pi editor
# Extracted some methods to reduce buffer size
class SamplerHelper
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
  end

  def play(bar, recording_grid, recording_sample, editing_sample)
    recording_grid.each do | recording_row |
      recording_row.each do | sample |
        if sample.bars != nil
          if bar % sample.bars == 0 and sample != recording_sample
            auto_color_sample(sample)
            if sample.buffer != nil and sample.is_playing
              retrigger = SessionMachine.retrigger
              if retrigger != nil and (@editing_sample == nil or sample == editing_sample)
                @sonic_pi.in_thread.call do
                  steps = 8.0 * sample.bars
                  @sonic_pi.time_warp.call (-1 * Clock.bpm / 60.0 * SessionMachine.latency) do
                    (steps / retrigger).times do
                      @sonic_pi.sample.call sample.buffer, amp: sample.amp, finish: retrigger / steps
                      @sonic_pi.sleep.call retrigger / 2.0
                    end
                  end
                end
              else
                if [:PLAY, :BACK].include? sample.mode
                  @sonic_pi.time_warp.call (-1 * Clock.bpm / 60.0 * SessionMachine.latency) do
                    @sonic_pi.sample.call sample.buffer, amp: sample.amp, rate: sample.mode == :PLAY ? 1 : -1
                  end
                else
                  @sonic_pi.in_thread.call do
                    steps = 4 * sample.bars
                    steps.times do | step |
                      slice_idx = rand(steps - 1)
                      slice_size = 1.0 / steps
                      start = slice_idx * slice_size
                      finish = start + slice_size
                      @sonic_pi.sample.call sample.buffer, amp: sample.amp, start: start, finish: finish, rate: (sample.mode == :SLICE or (sample.mode == :SLIDE_RAND and rand(1) == 1) ? 1 : -1)
                      @sonic_pi.sleep.call 1
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def auto_color_sample(sample)
    if sample.buffer != nil
      if sample.is_playing
        color_sample sample, PadColorPalette.green
      else
        color_sample sample, PadColorPalette.blue
      end
    else
      color_sample sample, PadColorPalette.black
    end
  end
  
  def color_sample(recording_sample, color)
    if SessionMachine.mode != :SESSION_MODE
      return
    end
    
    @push.color_row_column recording_sample.row, recording_sample.column, color
  end
end
