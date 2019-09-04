require_relative 'session-machine.rb'
require_relative 'helper.rb'
require_relative 'color-palette.rb'
require_relative 'multi-bar.rb'

class ChopSampler
  include MultiBar

  ChopTrack = Struct.new(:is_playing, :buffer, :bars, :amp, :reverb_mix, :reverb_control, :row, :column, :chops)
  Chop = Struct.new(:color, :start, :finish, :notes)
  ChopNote = Struct.new(:active)
  
  attr :chop_samples
  attr :recording_chop

  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @viewing_bar = 0
    @editing_chop = nil
    @recording_chop = nil
    @editing_chop_index = nil
    
    @chop_samples = []
    AbletonPush.chop_sample_row_size().times do | i |
      AbletonPush.pad_column_size().times do | j |
        @chop_samples.push(ChopTrack.new(false, nil, nil, 1.0, 0.0, nil, i + AbletonPush.drum_row_size(), j, [
                                           Chop.new(PadColorPalette.blue, 0, 1, []),
                                           Chop.new(PadColorPalette.green, 0, 1, []),
                                           Chop.new(PadColorPalette.red, 0, 1, []),
                                           Chop.new(PadColorPalette.teal, 0, 1, []),
                                           Chop.new(PadColorPalette.yellow, 0, 1, []),
                                           Chop.new(PadColorPalette.magenta, 0, 1, []),
                                           Chop.new(PadColorPalette.lime, 0, 1, []),
                                           Chop.new(PadColorPalette.violet, 0, 1, [])]))
      end
    end
    
    @sonic_pi.live_loop.call :chop_builder do
      @sonic_pi.sync.call :chop_builder_cue
      load_chop_track(@editing_chop)
    end
    
    @sonic_pi.live_loop.call :chop_record do
      @sonic_pi.sync.call :chop_record_cue
      @sonic_pi.live_audio.call :mon, :stop
      
      if @editing_chop != nil and @editing_chop.buffer != nil
        @sonic_pi.with_fx.call :sound_out_stereo, output: 100, amp: SessionMachine.mute_while_recording ? 0 : 1 do
          @sonic_pi.with_fx.call :record, buffer: @editing_chop.buffer, pre_amp: SessionMachine.recording_pre_amp do
            @sonic_pi.live_audio.call :record_chop, amp: 1, stereo: true
          end
        end
      end
    end
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  def load_chop_track(chop_track)
    steps = [*0..(SessionMachine.steps_per_bar - 1)].ring
    current_bar = 0
    @sonic_pi.with_fx.call :reverb do | r |
      chop_track.reverb_control = r
      @sonic_pi.live_loop.call "chop_sample_#{chop_track.row}_#{chop_track.column}" do
        step = steps.tick
        # Sync every bar to prevent drift
        if step == 0
          @sonic_pi.use_bpm.call Clock.bpm
          @sonic_pi.sync.call :master_cue
          
          current_bar = SessionMachine.current_bar
        end
        if chop_track != @recording_chop
          Helper.auto_color_track(@push, chop_track)
          if chop_track.bars != nil and chop_track.is_playing
            bar_step = current_bar % chop_track.bars * SessionMachine.steps_per_bar + step
            
            retrigger = SessionMachine.retrigger
            if retrigger != nil and (@editing_chop == nil or chop_track == @editing_chop)
              bar_step = bar_step % retrigger
            end
            chop_track.chops.each do | chops |
              note = chops.notes[bar_step]
              if note.active == true
                @sonic_pi.sample.call chop_track.buffer, amp: chop_track.amp, start: chops.start, finish: chops.finish
              end
            end
          end
        end
        @sonic_pi.sleep.call 0.5
      end
    end
  end
  
  def begin_record(track_number)
    if @editing_chop == nil or @editing_chop.buffer == nil
      @editing_chop = @recording_chop = @chop_samples[track_number]
      set_recording_bar_power()
      
      @editing_chop.buffer = @sonic_pi.buffer["chop_#{@editing_chop.row}_#{@editing_chop.column}"]
      @sonic_pi.cue.call :chop_record_cue
      Helper.color_track(@push, @editing_chop, PadColorPalette.red)
    end
  end
  
  def end_record()
    if @editing_chop != nil
      @recording_chop = nil
      @sonic_pi.live_audio.call :record_chop, :stop
      @editing_chop.is_playing = true
      @sonic_pi.cue.call :chop_builder_cue
    end
  end
  
  def toggle_play(track_number)
    chop_track = @chop_samples[track_number]
    chop_tracks.is_playing = !chop_tracks.is_playing
    Helper.color_track(@push, chop_track, PadColorPalette.grey)
  end
  
  def edit(track_number)
    @editing_chop = @editing_chops[track_number]
    set_recording_bar_power
  end
  
  def mode_change()
    if SessionMachine.mode == :CHOP_MODE
      set_viewing_bar(0)
      print_editing_menu()
    else
      @editing_chop = nil
      @chop_samples.each do | chop_track |
        Helper.auto_color_track(@push, chop_track)
      end
    end
  end
  
  def pad_callback(row, column, velocity)
    if SessionMachine.mode != :CHOP_MODE
      return
    end
    
    chop = @editing_chop.chops[row]
    viewing_chop_note = get_viewing_note(chop, column)
    viewing_chop_note.active = viewing_chop_note.active == false ? true : false
    @push.color_row_column row, column, viewing_chop_note.active == false ? PadColorPalette.black : chop.color
  end
  
  def control_callback(note, velocity)
    if SessionMachine.mode != :CHOP_MODE
      return
    end
    
    if [*36..43].include? note and velocity == 127
      chop_setting_update {
        chop_edit = note - 36
        @editing_chop_index = @editing_chop_index == chop_edit ? nil : chop_edit
      }
    elsif note == 44
      set_viewing_bar(@viewing_bar > 0 ? @viewing_bar - 1 : @viewing_bar)
    elsif note == 45
      set_viewing_bar(@viewing_bar < SessionMachine.recording_bars - 1 ? @viewing_bar + 1 : @viewing_bar)
    elsif note == 71
      chop_setting_update {
        @editing_chop.amp = (@editing_chop.amp + (velocity == 1 ? 0.01 : -0.01)).round(2)
      }
    elsif note == 72
      chop_setting_update {
        @editing_chop.reverb_mix = Helper.within(@editing_chop.reverb_mix + (velocity == 1 ? 0.02 : -0.02), 0.0, 1.0).round(2)
        @sonic_pi.control.call @editing_chop.reverb_control, mix: @editing_chop.reverb_mix
      }
    elsif note == 73
      if @editing_chop_index != nil
        chop_setting_update {
          @editing_chop.chops[@editing_chop_index].start = Helper.within(@editing_chop.chops[@editing_chop_index].start + (velocity == 1 ? 0.01 : -0.01), 0, 1).round(2)
        }
      end
    elsif note == 74
      if @editing_chop_index != nil
        chop_setting_update {
          @editing_chop.chops[@editing_chop_index].finish = Helper.within(@editing_chop.chops[@editing_chop_index].finish + (velocity == 1 ? 0.01 : -0.01), 0, 1).round(2)
        }
      end
    end
  end
  
  def chop_setting_update()
    if @editing_chop != nil
      yield
      print_editing_menu()
    end
  end
  
  def set_recording_bar_power()
    multi_bar_set_recording_bar_power(@editing_chop, @editing_chop&.chops, lambda{ ChopNote.new(false) })
  end
  
  def set_viewing_bar(viewing_bar)
    multi_bar_set_viewing_bar(viewing_bar, :CHOP_MODE) { draw_chop_notes() }
  end

  def draw_chop_notes()
    @editing_chop.chops.each_with_index do | chop, row |
      SessionMachine.steps_per_bar.times do | step |
        note = get_viewing_note(chop, step)
        @push.color_row_column row, step, note.active == false ? PadColorPalette.black : chop.color
      end
    end
  end

  def get_viewing_note(chop, column)
    return chop.notes[@viewing_bar * SessionMachine.steps_per_bar + column]
  end

  def print_editing_menu()
    if SessionMachine.mode != :CHOP_MODE
      return
    end
    
    if @editing_chop != nil
      @push.write_display(0, 1, "Chop")
      @push.write_display(1, 1, "Amp #{@editing_chop.amp}")
      @push.write_display(2, 1, "Reverb #{@editing_chop.reverb_mix}")
    end
    
    if @editing_chop_index != nil
      @push.write_display(0, 2, "Chop Sample")
      @push.write_display(1, 2, "Start #{@editing_chop.chops[@editing_chop_index].start}")
      @push.write_display(2, 2, "Finish #{@editing_chop.chops[@editing_chop_index].finish}")
    else
      @push.clear_display_section(0, 2)
      @push.clear_display_section(1, 2)
      @push.clear_display_section(2, 2)
    end
  end
end
