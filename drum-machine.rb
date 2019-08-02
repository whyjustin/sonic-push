require_relative 'clock.rb'
require_relative 'color-palette.rb'
require_relative 'session-machine.rb'
require_relative 'helper.rb'
require_relative 'drum-machine-helper.rb'

class DrumMachine
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    @drum_machine_helper = DrumMachineHelper.new(@sonic_pi, @push)
    
    @mode = :DRUM_NOTE_MODE
    @current_drum_edit = 0
    
    @drum_steps_per_bar = SessionMachine.steps_per_bar * 2
    

    @kits = [ @drum_machine_helper.get_default_kit() ]
    
    @drum_tracks = @drum_machine_helper.build_drum_tracks()
    
    @is_active_mode = false
    
    steps = [*0..(@drum_steps_per_bar - 1)].ring
    current_bar = 0
    @drum_tracks.each do | drum_track |
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
            @drum_machine_helper.auto_color_drum_track(@is_active_mode, drum_track)
            if drum_track.bars != nil and drum_track.is_playing
              bar_step = current_bar % drum_track.bars * @drum_steps_per_bar + step
              
              retrigger = SessionMachine.retrigger
              if retrigger != nil and (@editing_drums == nil or drum_track == @editing_drums)
                bar_step = bar_step % retrigger
              end
              
              kit = @kits[drum_track.kit_index]
              drum_track.drums.each_with_index do | drum, index |
                if kit.is_a? String
                  @sonic_pi.sample.call kit, index, amp: drum.notes[bar_step].volume / 8.0 if drum.notes[bar_step].active == true
                else
                  @sonic_pi.sample.call kit[index], amp: drum.notes[bar_step].volume / 8.0 if drum.notes[bar_step].active == true
                end
              end
            end
          end
          @sonic_pi.sleep.call 0.5
        end
      end
      
      #Throttle Initialization
      @sonic_pi.sleep.call 0.1
    end
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  def drum_tracks()
    return @drum_tracks
  end
  
  def toggle_play(track_number)
    drum_track = @drum_tracks[track_number]
    drum_track.is_playing = !drum_track.is_playing
    @drum_machine_helper.color_drum_track @is_active_mode, drum_track, PadColorPalette.grey
  end
  
  def edit(track_number)
    @editing_drums = @drum_tracks[track_number]
    set_recording_bar_power
  end
  
  def load_kit(kit)
    @kits.push(kit)
  end
  
  def set_recording_bar_power()
    if @editing_drums != nil
      i = 0
      until i > SessionMachine.recording_bars - 1
        bar_step = i * @drum_steps_per_bar
        if @editing_drums.drums[0].notes.length <= bar_step
          @editing_drums.drums.each do | drum |
            @drum_steps_per_bar.times do | j |
              step = bar_step + j
              last_bar_step = step - @drum_steps_per_bar
              if last_bar_step >= 0 and drum.notes.length >= last_bar_step
                drum.notes.push(drum.notes[last_bar_step].dup)
              else
                drum.notes.push(DrumMachineHelper::DrumNote.new(false, 4))
              end
            end
          end
        end
        i = i + 1
      end
      @editing_drums.bars = SessionMachine.recording_bars
    end
  end
  
  def set_viewing_bar()
    switch_mode @mode
  end
  
  def get_drum_steps
    return SessionMachine.recording_steps * 2
  end
  
  def is_active_mode=is_active_mode
    @is_active_mode = is_active_mode
    if is_active_mode
      switch_mode(:DRUM_NOTE_MODE)
      @drum_machine_helper.print_editing_menu(@is_active_mode, @editing_drums)
    else
      @drum_machine_helper.clear_editing_menu()
      @editing_drums = nil
      @drum_tracks.each do | drum_track |
        @drum_machine_helper.auto_color_drum_track(@is_active_mode, drum_track)
      end
    end
  end
  
  def switch_mode(mode)
    @mode = mode
    case @mode
    when :DRUM_NOTE_MODE
      @push.clear
      @sonic_pi.sleep.call 0.1
      @editing_drums.drums.each_with_index do | drum, row |
        @drum_steps_per_bar.times do | step |
          note = get_viewing_note(drum, step)
          @push.color_row_column row, step, note.active == false ? PadColorPalette.black : drum.color
        end
      end
    when :DRUM_EDIT_MODE
      @push.clear
      @sonic_pi.sleep.call 0.1
      drum = @editing_drums.drums[@current_drum_edit]
      @drum_steps_per_bar.times do | step |
        note = get_viewing_note(drum, step)
        8.times do | volume |
          @push.color_row_column volume, step, volume <= note.volume ? drum.color : PadColorPalette.black
        end
      end
    end
  end
  
  def pad_callback(row, column, velocity)
    if not @is_active_mode
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
      @drum_steps_per_bar.times do | volume |
        @push.color_row_column volume, column, volume <= row ? drum.color : PadColorPalette.black
      end
    end
  end
  
  def control_callback(note, velocity)
    if not @is_active_mode
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
    elsif note == 71
      drum_setting_update {
        @editing_drums.swing = Helper.within(@editing_drums.swing + (velocity == 1 ? 0.01 : -0.01), -0.5, 0.5).round(2)
      }
    elsif note == 72
      drum_setting_update {
        @editing_drums.reverb_mix = Helper.within(@editing_drums.reverb_mix + (velocity == 1 ? 0.05 : -0.05), 0.0, 1.0).round(2)
        @sonic_pi.control.call @editing_drums.reverb_control, mix: @editing_drums.reverb_mix
      }
    elsif note == 73
      drum_setting_update {
        @editing_drums.kit_index = Helper.within(@editing_drums.kit_index + (velocity == 1 ? 1 : -1), 0, @kits.length - 1).round(0)
      }
    end
  end
  
  def drum_setting_update
    if @editing_drums != nil
      yield
      @drum_machine_helper.print_editing_menu(@is_active_mode, @editing_drums)
    end
  end
  
  def get_viewing_note(drum, column)
    return drum.notes[SessionMachine.viewing_bar * @drum_steps_per_bar + column]
  end
end
