require_relative 'clock.rb'
require_relative 'color-palette.rb'
require_relative 'session-machine.rb'
require_relative 'helper.rb'
require_relative 'multi-bar.rb'

class DrumMachine
  include MultiBar

  attr :drum_tracks

  DrumTrack = Struct.new(:kit_index, :is_playing, :bars, :amp, :swing, :reverb_mix, :reverb_control, :row, :column, :drums)
  Drum = Struct.new(:color, :notes)
  DrumNote = Struct.new(:active, :volume)

  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @mode = :DRUM_NOTE_MODE
    @current_drum_edit = 0
    
    @kits = [ 
      [
        :drum_bass_hard,
        :drum_snare_hard,
        :drum_tom_lo_hard,
        :drum_tom_mid_hard,
        :drum_tom_hi_hard,
        :drum_cowbell,
        :drum_cymbal_closed,
        :drum_cymbal_open
      ] 
    ]
    
    @drum_tracks = []
    AbletonPush.drum_row_size().times do | i |
      AbletonPush.pad_column_size().times do | j |
        @drum_tracks.push(DrumTrack.new(0, false, nil, 1.0, 0, 0.0, nil, i, j, [
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
    
    @viewing_bar = 0
    @is_active_mode = false

    @sonic_pi.live_loop.call :drum_builder do
      @sonic_pi.sync.call :drum_builder_cue
      load_drum_track(@editing_drums)
    end

    @push.register_pad_callback(method(:pad_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  def load_drum_track(drum_track)
    steps = [*0..(SessionMachine.steps_per_bar - 1)].ring
    current_bar = 0
    @sonic_pi.with_fx.call :reverb do | r |
      drum_track.reverb_control = r
      @sonic_pi.live_loop.call "drum_machine_#{drum_track.row}_#{drum_track.column}" do
        step = steps.tick
        # Sync every bar to prevent drift
        if step == 0
          @sonic_pi.use_bpm.call Clock.bpm
          @sonic_pi.sync.call :master_cue
          
          current_bar = SessionMachine.current_bar
        end
        @sonic_pi.with_swing.call drum_track.swing, pulse: 2 do
          Helper.auto_color_track(@push, drum_track)
          if drum_track.bars != nil and drum_track.is_playing
            bar_step = current_bar % drum_track.bars * SessionMachine.steps_per_bar + step
            
            retrigger = SessionMachine.retrigger
            if retrigger != nil and (@editing_drums == nil or drum_track == @editing_drums)
              bar_step = bar_step % retrigger
            end

            kit = @kits[drum_track.kit_index]
            drum_track.drums.each_with_index do | drum, index |
              if drum.notes[bar_step].active == true
                if kit.is_a? String
                  @sonic_pi.sample.call kit, index, amp: drum_track.amp * drum.notes[bar_step].volume / 4.0
                else
                  @sonic_pi.sample.call kit[index], amp: drum_track.amp * drum.notes[bar_step].volume / 4.0
                end
              end
            end
          end
        end
        @sonic_pi.sleep.call 0.5
      end
    end
  end
  
  def toggle_play(track_number)
    drum_track = @drum_tracks[track_number]
    drum_track.is_playing = !drum_track.is_playing
    Helper.color_track(@push, drum_track, PadColorPalette.grey)
  end
  
  def edit(track_number)
    @editing_drums = @drum_tracks[track_number]
    if @editing_drums.bars == nil
      @sonic_pi.cue.call :drum_builder_cue
    end
    set_recording_bar_power
  end
  
  def load_kit(kit)
    @kits.push(kit)
  end
  
  def set_recording_bar_power()
    multi_bar_set_recording_bar_power(@editing_drums, @editing_drums&.drums, lambda{ DrumNote.new(false, 4) })
  end
  
  def set_viewing_bar(viewing_bar)
    multi_bar_set_viewing_bar(viewing_bar, :DRUM_MODE) { draw_drum_notes() }
  end
  
  def is_active_mode=is_active_mode
    @is_active_mode = is_active_mode
    if is_active_mode
      set_viewing_bar(0)
      switch_mode(:DRUM_NOTE_MODE)
      print_editing_menu()
    else
      @editing_drums = nil
      @drum_tracks.each do | drum_track |
        Helper.auto_color_track(@push, drum_track)
      end
    end
  end
  
  def switch_mode(mode)
    @mode = mode
    case @mode
    when :DRUM_NOTE_MODE
      draw_drum_notes()
    when :DRUM_EDIT_MODE
      drum = @editing_drums.drums[@current_drum_edit]
      SessionMachine.steps_per_bar.times do | step |
        note = get_viewing_note(drum, step)
        8.times do | volume |
          @push.color_row_column volume, step, volume <= note.volume ? drum.color : PadColorPalette.black
        end
      end
    end
  end
  
  def pad_callback(row, column, velocity)
    if SessionMachine.mode != :DRUM_MODE
      return
    end
    
    case @mode
    when :DRUM_NOTE_MODE
      drum = @editing_drums.drums[row]
      viewing_drum = get_viewing_note(drum, column)
      viewing_drum.active = viewing_drum.active == false ? true : false
      @push.color_row_column row, column, viewing_drum.active == false ? PadColorPalette.black : drum.color
    when :DRUM_EDIT_MODE
      drum = @editing_drums.drums[@current_drum_edit]
      viewing_drum = get_viewing_note(drum, column)
      viewing_drum.volume = row + 1
      SessionMachine.steps_per_bar.times do | volume |
        @push.color_row_column volume, column, volume <= row ? drum.color : PadColorPalette.black
      end
    end
  end
  
  def control_callback(note, velocity)
    if SessionMachine.mode != :DRUM_MODE
      return
    end
    
    if [*36..43].include? note and velocity == 127
      drum_edit = note - 36
      if (@current_drum_edit == drum_edit and @mode == :DRUM_EDIT_MODE)
        switch_mode :DRUM_NOTE_MODE
      else
        @current_drum_edit = drum_edit
        switch_mode :DRUM_EDIT_MODE
      end
    elsif note == 44
      set_viewing_bar(@viewing_bar > 0 ? @viewing_bar - 1 : @viewing_bar)
    elsif note == 45
      set_viewing_bar(@viewing_bar < SessionMachine.recording_bars - 1 ? @viewing_bar + 1 : @viewing_bar)
    elsif note == 71
      drum_setting_update {
        @editing_drums.amp = (@editing_drums.amp + (velocity == 1 ? 0.01 : -0.01)).round(2)
      }
    elsif note == 72
      drum_setting_update {
        @editing_drums.swing = Helper.within(@editing_drums.swing + (velocity == 1 ? 0.01 : -0.01), -0.5, 0.5).round(2)
      }
    elsif note == 73
      drum_setting_update {
        @editing_drums.reverb_mix = Helper.within(@editing_drums.reverb_mix + (velocity == 1 ? 0.02 : -0.02), 0.0, 1.0).round(2)
        @sonic_pi.control.call @editing_drums.reverb_control, mix: @editing_drums.reverb_mix
      }
    elsif note == 74
      drum_setting_update {
        @editing_drums.kit_index = Helper.within(@editing_drums.kit_index + (velocity == 1 ? 1 : -1), 0, @kits.length - 1).round(0)
      }
    end
  end
  
  def drum_setting_update
    if @editing_drums != nil
      yield
      print_editing_menu()
    end
  end

  def print_editing_menu()
    if SessionMachine.mode != :DRUM_MODE
      return
    end
    
    if @editing_drums != nil
      @push.write_display(0, 1, "Drum")
      @push.write_display(1, 1, "Amp #{@editing_drums.amp}")
      @push.write_display(2, 1, "Swing #{@editing_drums.swing}")
      @push.write_display(3, 1, "Reverb #{@editing_drums.reverb_mix}")
      kit = @kits[@editing_drums.kit_index]
      kit_display = (kit.is_a? String) ? kit.match(/(?:.(?!\/))+$/)[0] : @editing_drums.kit_index
      @push.write_display(0, 2, "Kit #{kit_display}")
    end
  end

  def draw_drum_notes()
    @editing_drums.drums.each_with_index do | drum, row |
      SessionMachine.steps_per_bar.times do | step |
        note = get_viewing_note(drum, step)
        @push.color_row_column row, step, note.active == false ? PadColorPalette.black : drum.color
      end
    end
  end
  
  def get_viewing_note(drum, column)
    return drum.notes[@viewing_bar * SessionMachine.steps_per_bar + column]
  end
end
