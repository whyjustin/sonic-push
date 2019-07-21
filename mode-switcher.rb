class ModeSwitcher
  def initialize(sonic_pi, push, session_machine, drum_machine)
    @sonic_pi = sonic_pi
    @push = push
    @session_machine = session_machine
    @drum_machine = drum_machine
    
    @push.register_control_callback(method(:control_callback))
  end
  
  def control_callback(note, velocity)
    if velocity == 127
      switch_mode note == 50 ? :DRUM_MODE : :SESSION_MODE
    end
  end
  
  def switch_mode(mode)
    case mode
    when :DRUM_MODE
      @session_machine.is_active_mode = false
      @sonic_pi.sleep.call 0.5
      @push.clear
      @drum_machine.is_active_mode = true
      @push.color_note 50, NoteColorPallete.lit
      @push.color_note 51, NoteColorPallete.dim
    when :SESSION_MODE
      @drum_machine.is_active_mode = false
      @sonic_pi.sleep.call 0.5
      @push.clear
      @session_machine.is_active_mode = true
      @push.color_note 50, NoteColorPallete.dim
      @push.color_note 51, NoteColorPallete.lit
    end
  end
end
