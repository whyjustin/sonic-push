require_relative 'session-machine.rb'
require_relative 'ableton-push.rb'
require_relative 'helper.rb'
require_relative 'synthesizer-helper.rb'
require_relative 'step-sequence.rb'
require_relative 'multi-bar.rb'

class Synthesizer
  include MultiBar

  attr :synth_tracks

  SynthTrack = Struct.new(:instrument_index, :is_playing, :bars, :mode, :drunk_state, :row, :column, :steps)
  NoteStep = Struct.new(:notes)
  Note = Struct.new(:active, :length)

  def self.steps_per_bar
    return SessionMachine.steps_per_bar * 2
  end
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    @synthesizer_helper = SynthesizerHelper.new(@sonic_pi, @push)
    
    @viewing_bar = 0
    @editing_synth = nil
    @instruments = [
      :prophet
    ]
    @recording_instrument_index = 0
    @scale_index = 0
    @total_notes = 88
    @viewing_note_index = 36
    
    @synth_tracks = []
    AbletonPush.synth_row_size().times do | i |
      AbletonPush.pad_column_size().times do | j |
        track = SynthTrack.new(0, false, nil, :PLAY, 0, i + AbletonPush.pad_row_size() - AbletonPush.synth_row_size(), j, [])
        @synth_tracks.push(track)
      end
    end
    
    @recording_offet = -1 * SessionMachine.latency
    @quantize_step = :FULL_NOTE
    @step_sequence = StepSequence.new
    @sonic_pi.in_thread.call do
      @sonic_pi.loop.call do
        @sonic_pi.use_real_time.call
        event_selector = "/midi/*/*/*/{note_on,note_off}"
        note, velocity = @sonic_pi.sync.call event_selector
        if @editing_synth != nil
          event = @sonic_pi.get_event.call(event_selector).to_s.split(",")[6]
          if event != nil
            event_source = event[2..-2].split("/")
            event_midi = event_source[2]
            if event_midi == @instruments[@recording_instrument_index]
              @step_sequence.add_step(Step.new(note))
              @sonic_pi.cue.call :step_sequence_builder_cue
            end
          end
        end
      end
    end

    @sonic_pi.in_thread.call do
      @sonic_pi.loop.call do
        @sonic_pi.sync.call :step_sequence_builder_cue
        if @editing_synth != nil
          @sonic_pi.time_warp.call (Clock.bpm / 60.0 * @recording_offet) do
            editing_step = @sonic_pi.get[:editing_step]
            i = 0
            while i < @step_sequence.length do
              step = @step_sequence.get_step(i)
              if step.step == nil
                step.step = editing_step
              end
              j = i + 1
              while j < @step_sequence.length do
                next_step = @step_sequence.get_step(j)
                if next_step.note == step.note
                  step_note = @editing_synth.steps[step.step].notes[step.note]
                  step_note.active = true
                  if editing_step >= step.step
                    step_note.length = editing_step - step.step + 1.0
                  else
                    step_note.length = editing_step - step.step + @editing_synth.bars * Synthesizer.steps_per_bar + 1.0
                  end

                  @step_sequence.remove_step(j)
                  @step_sequence.remove_step(i)

                  i -= 1
                  break
                end
                j += 1
              end
              i += 1
            end
            draw_synth_notes()
          end
        end
      end
    end
    
    @push.register_pad_callback(method(:pad_callback))
    @push.register_control_callback(method(:control_callback))
  end
  
  def play(current_bar)
    @sonic_pi.in_thread.call do
      Synthesizer.steps_per_bar.times do | step |
        if @editing_synth != nil
          @sonic_pi.set.call :editing_step, current_bar % @editing_synth.bars * Synthesizer.steps_per_bar + (@quantize_step == :FULL_NOTE ? step.to_i / 2 * 2 : step)
        end
        @synth_tracks.each do | synth_track |
          @synthesizer_helper.auto_color_synth_track(synth_track)
          if synth_track.is_playing
            if synth_track.mode == :PLAY
              bar_step = current_bar % synth_track.bars * Synthesizer.steps_per_bar + step
            elsif synth_track.mode == :BACK
              bar_step = synth_track.bars * Synthesizer.steps_per_bar - (current_bar % synth_track.bars * Synthesizer.steps_per_bar + step) - 1
            elsif synth_track.mode == :DRUNK
              state = synth_track.drunk_state += [-1, 0, 1].sample
              if state < 0
                state = synth_track.bars * Synthesizer.steps_per_bar - 1
              elsif state >= synth_track.bars * Synthesizer.steps_per_bar - 1
                state = 0
              end
              synth_track.drunk_state = state
              bar_step = synth_track.drunk_state
            end
            step_notes = synth_track.steps[bar_step]
            synth = @instruments[synth_track.instrument_index]
            
            if !synth.is_a? String
              @sonic_pi.use_synth.call synth
            end
            
            step_notes.notes.each_with_index do | note, note_index |
              if note.active
                if !synth.is_a? String
                  @sonic_pi.play.call note_index, sustain: note.length * 0.25, release: 0.25
                else
                  @sonic_pi.midi.call note_index, port: synth, sustain: note.length * 0.25, release: 0.25
                end
              end
            end
          end
        end
        @sonic_pi.sleep.call 0.25
      end
    end
  end
  
  def toggle_play(track_number)
    synth_track = @synth_tracks[track_number]
    synth_track.is_playing = !synth_track.is_playing
    @synthesizer_helper.color_synth_track(synth_track, PadColorPalette.grey)
  end
  
  def edit(track_number)
    @editing_synth = @synth_tracks[track_number]
    set_recording_bar_power()
  end
  
  def load_synth(synth)
    @instruments.push(synth)
  end
  
  def set_recording_bar_power()
    if @editing_synth != nil
      i = 0
      until i > SessionMachine.recording_bars - 1
        bar_step = i * Synthesizer.steps_per_bar
        if @editing_synth.steps.length <= bar_step
          Synthesizer.steps_per_bar.times do | j |
            step = bar_step + j
            last_bar_step = step - Synthesizer.steps_per_bar
            if last_bar_step >= 0 and @editing_synth.steps.length >= last_bar_step
              @editing_synth.steps.push(NoteStep.new(Array.new(@total_notes) { | j | @editing_synth.steps[last_bar_step].notes[j].dup }))
            else
              @editing_synth.steps.push(NoteStep.new(Array.new(@total_notes) { Note.new(false, 2) }))
            end
          end
        end
        i = i + 1
      end
      @editing_synth.bars = SessionMachine.recording_bars
      set_viewing_bar @viewing_bar >= SessionMachine.recording_bars ? SessionMachine.recording_bars - 1 : @viewing_bar
    end
  end
  
  def pad_callback(row, column, velocity)
    if SessionMachine.mode != :SYNTH_MODE
      return
    end
    
    note_step = @synthesizer_helper.get_viewing_note_step(@editing_synth, column * 2, @viewing_bar)
    hidden_note_step = @synthesizer_helper.get_viewing_note_step(@editing_synth, column * 2 + 1, @viewing_bar)
    viewing_note = note_step.notes[row + @viewing_note_index]
    hidden_viewing_note = hidden_note_step.notes[row + @viewing_note_index]

    if viewing_note.active or hidden_viewing_note.active
      viewing_note.active = hidden_viewing_note.active = false
    else
      viewing_note.active = true
    end
    draw_synth_notes()
  end
  
  def control_callback(note, velocity)
    if SessionMachine.mode != :SYNTH_MODE
      return
    end

    if velocity == 127
      if note == 44
        set_viewing_bar(@viewing_bar > 0 ? @viewing_bar - 1 : @viewing_bar)
      elsif note == 45
        set_viewing_bar(@viewing_bar < SessionMachine.recording_bars - 1 ? @viewing_bar + 1 : @viewing_bar)
      elsif note == 46
        set_viewing_note_index(@viewing_note_index + AbletonPush.pad_row_size())
      elsif note == 47
        set_viewing_note_index(@viewing_note_index - AbletonPush.pad_row_size())
      end
    end
    
    if note == 71
      if @editing_synth != nil
        @editing_synth.instrument_index = Helper.within(@editing_synth.instrument_index + (velocity == 1 ? 1 : -1), 0, @instruments.length - 1).round(0)
        print_editing_menu()
      end
    elsif note == 72
      @scale_index = Helper.within(@scale_index + (velocity == 1 ? 1 : -1), 0, SynthesizerHelper.scales.length - 1).round(0)
      print_editing_menu()
      draw_synth_notes()
    elsif note == 73
      if @editing_synth != nil
        @editing_synth.mode = next_mode(@editing_synth.mode)
        print_editing_menu()
      end
    elsif note == 74
      @recording_instrument_index = Helper.within(@recording_instrument_index + (velocity == 1 ? 1 : -1), 0, @instruments.length - 1).round(0)
      print_editing_menu()
    elsif note == 75
      @recording_offet = Helper.within(@recording_offet + (velocity == 1 ? 0.01 : -0.01), -0.50, 0.00).round(2)
      print_editing_menu()
    elsif note == 76
      @quantize_step = next_quantize_step(@quantize_step)
      print_editing_menu()
    end
  end
  
  def mode_change()
    print_editing_menu()
    
    if SessionMachine.mode == :SYNTH_MODE
      set_viewing_bar(0)
      draw_synth_notes()
      set_viewing_note_index(@viewing_note_index)
    else
      @editing_synth = nil
      @synth_tracks.each do | synth_track |
        @synthesizer_helper.auto_color_synth_track(synth_track)
      end
    end
  end

  def next_mode(mode)
    case mode
    when :PLAY
      return :BACK
    when :BACK
      return :DRUNK
    when :DRUNK
      return :PLAY
    end
  end

  def next_quantize_step(quantize_step)
    case quantize_step
    when :FULL_NOTE
      return :HALF_NOTE
    when :HALF_NOTE
      return :FULL_NOTE
    end
  end
  
  def set_viewing_bar(viewing_bar)
    multi_bar_set_viewing_bar(viewing_bar, :SYNTH_MODE) { draw_synth_notes() }
  end
  
  def set_viewing_note_index(viewing_note_index)
    @viewing_note_index = Helper.within(viewing_note_index, 0, @total_notes - AbletonPush.pad_row_size())
    
    @push.color_note 46, @viewing_note_index < @total_notes - AbletonPush.pad_row_size() ? NoteColorPalette.lit : NoteColorPalette.off
    @push.color_note 47, @viewing_note_index != 0 ? NoteColorPalette.lit : NoteColorPalette.off
    draw_synth_notes()
  end
  
  def draw_synth_notes()
    if SessionMachine.mode != :SYNTH_MODE
      return
    end
    Synthesizer.steps_per_bar.times do | step |
      if step % 2 == 0
        viewing_note_step = @synthesizer_helper.get_viewing_note_step(@editing_synth, step, @viewing_bar)
        viewing_note_hidden_step = @synthesizer_helper.get_viewing_note_step(@editing_synth, step + 1, @viewing_bar)
        [*@viewing_note_index..(@viewing_note_index + AbletonPush.pad_row_size() - 1)].each do | note_index |
          selected_scale = SynthesizerHelper.scales[@scale_index]
          scale_note = note_index % 12
          view_note = note_index - @viewing_note_index
          if viewing_note_step.notes[note_index].active or viewing_note_hidden_step.notes[note_index].active
            @push.color_row_column(view_note, step / 2, PadColorPalette.green)
          elsif scale_note == selected_scale.base_note
            @push.color_row_column(view_note, step / 2, PadColorPalette.blue)
          elsif selected_scale.notes.include? scale_note
            @push.color_row_column(view_note, step / 2, PadColorPalette.grey)
          else
            @push.color_row_column(view_note, step / 2, PadColorPalette.black)
          end
        end
      end
    end
  end

  def print_editing_menu()
    if SessionMachine.mode != :SYNTH_MODE
      return
    end
    
    if @editing_synth != nil
      @push.write_display(0, 1, "Synth")
      @push.write_display(1, 1, "Inst #{@instruments[@editing_synth.instrument_index]}")
      @push.write_display(2, 1, "Key #{SynthesizerHelper.scales[@scale_index].name}")
      @push.write_display(3, 1, "Mode #{@editing_synth.mode.to_s}")
      @push.write_display(0, 2, "Rec #{@instruments[@recording_instrument_index]}")
      @push.write_display(1, 2, "Offset #{@recording_offet}")
      @push.write_display(2, 2, "Quant #{@quantize_step.to_s}")
    end
  end
end
