# Welcome to Sonic Pi v3.1
SonicPiWrapper = Struct.new(:in_thread, :loop, :live_loop, :use_bpm, :sleep, :sync, :use_real_time, :tick, :look, :midi_cc, :midi_sysex, :sample, :buffer, :live_audio, :with_fx, :cue, :time_warp, :puts, :with_swing, :control, :set_mixer_control, :sample_duration)
sonic_pi = SonicPiWrapper.new(method(:in_thread), method(:loop), method(:live_loop), method(:use_bpm), method(:sleep), method(:sync), method(:use_real_time), method(:tick), method(:look), method(:midi_cc), method(:midi_sysex), method(:sample), buffer, method(:live_audio), method(:with_fx), method(:cue), method(:time_warp), method(:puts), method(:with_swing), method(:control), method(:set_mixer_control!), method(:sample_duration))

require '~/whyjustin/sonic-push/ableton-push.rb'
require '~/whyjustin/sonic-push/clock.rb'
require '~/whyjustin/sonic-push/drum-machine.rb'
require '~/whyjustin/sonic-push/sampler.rb'
require '~/whyjustin/sonic-push/session-machine.rb'


push = AbletonPush.new(sonic_pi)

drum_machine = DrumMachine.new(sonic_pi, push)
sampler = Sampler.new(sonic_pi, push)
session_machine = SessionMachine.new(sonic_pi, push, sampler, drum_machine)
metronome = Clock.new(sonic_pi, push)

##| TR808 = "path/to/sonic-push/kits/808"
##| drum_machine.load_kit TR808
