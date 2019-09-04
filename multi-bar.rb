module MultiBar
  def multi_bar_set_recording_bar_power(editing, sounds, new_note_function)
    if editing != nil
      i = 0
      until i > SessionMachine.recording_bars - 1
        bar_step = i * SessionMachine.steps_per_bar
        if sounds[0].notes.length <= bar_step
          sounds.each do | sound |
            SessionMachine.steps_per_bar.times do | j |
              step = bar_step + j
              last_bar_step = step - SessionMachine.steps_per_bar
              if last_bar_step >= 0 and sound.notes.length >= last_bar_step
                sound.notes.push(sound.notes[last_bar_step].dup)
              else
                sound.notes.push(new_note_function.call())
              end
            end
          end
        end
        i = i + 1
      end
      editing.bars = SessionMachine.recording_bars
      set_viewing_bar @viewing_bar >= SessionMachine.recording_bars ? SessionMachine.recording_bars - 1 : @viewing_bar
    end
  end

  def multi_bar_set_viewing_bar(viewing_bar, mode)
    if SessionMachine.mode == mode
      @viewing_bar = viewing_bar
      @push.color_note 44, @viewing_bar != 0 ? NoteColorPalette.lit : NoteColorPalette.off
      @push.color_note 45, @viewing_bar != SessionMachine.recording_bars - 1 ? NoteColorPalette.lit : NoteColorPalette.off
      yield
    end
  end
end
