# Welcome to Sonic Pi v3.1
Color = Struct.new(:red, :green, :blue)

class PadColorPallete
  def self.black
    return Color.new(0, 0, 0)
  end
  
  def self.green
    return Color.new(0, 255, 0)
  end
  
  
  def self.red
    return Color.new(255, 0, 0)
  end
end

class SecondStripColorPallete
  def self.black
    return 0
  end
  
  def self.red
    return 5
  end
end

class Clock
  @@bpm = 60
  
  def initialize(sonic_pi, push)
    @enable = false
    @monitor_active = false
    @beats = [2,0,1,0,1,0,1,0]
    
    sonic_pi.live_loop.call :metronome do
      sonic_pi.use_bpm.call @@bpm
      sonic_pi.sync.call :master_cue
      push.register_control_callback(method(:control_callback))
      
      if @enable
        beat = @beats.ring.tick
        sonic_pi.sample.call :elec_tick, amp: 1, rate: 0.8 if beat == 1
        sonic_pi.sample.call :elec_tick, amp: 2 if beat == 2
      end
      if @monitor_active
        sonic_pi.live_audio.call :mon, stereo: true
      else
        sonic_pi.live_audio.call :mon, :stop
      end
      sonic_pi.sleep.call 0.5
    end
  end
  
  def self.bpm
    @@bpm
  end
  
  def control_callback(note, velocity)
    if velocity == 127
      if note == 9
        @enable = !@enable
      elsif note == 3
        @monitor_active = !@monitor_active
      end
    end
  end
end



SonicPiWrapper = Struct.new(:in_thread, :loop, :live_loop, :use_bpm, :sleep, :sync, :use_real_time, :tick, :look, :midi_cc, :midi_sysex, :sample, :buffer, :live_audio, :with_fx, :cue, :time_warp)
sonic_pi = SonicPiWrapper.new(method(:in_thread), method(:loop), method(:live_loop), method(:use_bpm), method(:sleep), method(:sync), method(:use_real_time), method(:tick), method(:look), method(:midi_cc), method(:midi_sysex), method(:sample), buffer, method(:live_audio), method(:with_fx), method(:cue), method(:time_warp))

require '~/whyjustin/sonic-push/ableton-push.rb'
require '~/whyjustin/sonic-push/drum-machine.rb'
# require '~/whyjustin/sonic-push/session-machine.rb'

class SessionMachine
  SamplePad = Struct.new(:buffer, :is_playing, :length, :row, :column)
  
  def initialize(sonic_pi, push)
    @sonic_pi = sonic_pi
    @push = push
    
    @recording_grid = Array.new(8) { |i| Array.new(8) { |j| SamplePad.new(nil, false, nil, i, j) } }
    @recording_sample = nil
    @recording_length = 4
    @monitor_active = false
    
    @push.clear
    @push.register_note_callback(method(:note_callback))
    @push.register_control_callback(method(:control_callback))
    
    4.times do | length_power |
      length = 2 ** (length_power) * 4
      
      @sonic_pi.live_loop.call "record_#{length}" do
        @sonic_pi.use_bpm.call Clock.bpm
        @sonic_pi.sync.call :master_cue
        
        if @recording_sample != nil and @recording_sample.length == length
          (2 * length).times do | i |
            @sonic_pi.sample.call :elec_tick
            @push.color_row_column @recording_sample.row, @recording_sample.column, i % 2 == 1 ? PadColorPallete.red : PadColorPallete.black
            @sonic_pi.sleep.call 0.5
          end
          
          @sonic_pi.in_thread.call do
            (2 * length).times do | i |
              @sonic_pi.sample.call :elec_tick
              @push.color_row_column @recording_sample.row, @recording_sample.column, i % 2 == 1 ? PadColorPallete.red : PadColorPallete.black
              @sonic_pi.sleep.call 0.5
            end
          end
          
          @recording_sample.buffer = @sonic_pi.buffer["sample_#{@recording_sample.row}_#{@recording_sample.column}", length]
          
          @sonic_pi.live_audio.call :mon, :stop
          @sonic_pi.sync.call :master_cue
          @sonic_pi.with_fx.call :record, buffer: @recording_sample.buffer do
            @sonic_pi.live_audio.call :rec, stereo: true
          end
          @sonic_pi.sleep.call length
          
          @recording_sample.is_playing = true
          @push.color_row_column @recording_sample.row, @recording_sample.column, PadColorPallete.green
          
          @sonic_pi.live_audio.call :rec, :stop
          @recording_sample = nil
          
          if @monitor_active
            @sonic_pi.live_audio.call :mon, stereo: true
          end
        else
          @sonic_pi.sleep.call length
        end
      end
    end
    
    4.times do | length_power |
      length = 2 ** (length_power) * 4
      @sonic_pi.live_loop.call "play_#{length}" do
        @sonic_pi.use_bpm.call Clock.bpm
        @sonic_pi.sync.call :master_cue
        
        @recording_grid.each do | recording_row |
          recording_row.each do | sample |
            if sample.buffer != nil and sample.is_playing and sample.length == length
              @sonic_pi.sample.call sample.buffer
            end
          end
        end
        
        @sonic_pi.sleep.call length
      end
    end
  end
  
  def note_callback(row, column, velocity)
    sample = @recording_grid[row][column]
    if sample.buffer
      sample.is_playing = !sample.is_playing
    end
  end
  
  def control_callback(note, velocity)
    if velocity = 127
      if [*36..43].include? note
        record note - 36
      elsif [*102..105].include? note
        @recording_length = (note - 101) * 4
      end
    end
  end
  
  def record(row)
    if @recording_sample != nil
      return
    end
    
    sample = @recording_grid[row].find { | sample | sample.buffer == nil }
    sample.length = @recording_length
    @recording_sample = sample
  end
end

push = AbletonPush.new(sonic_pi)

##| drum_machine = DrumMachine.new(sonic_pi, push)
session_machine = SessionMachine.new(sonic_pi, push)
metronome = Clock.new(sonic_pi, push)

use_bpm Clock.bpm

live_loop :master do
  cue :master_cue
  use_bpm Clock.bpm
  
  sleep 0.125
end
