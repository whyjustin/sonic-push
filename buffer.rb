SonicPiWrapper = Struct.new(:in_thread, :loop, :live_loop, :use_bpm, :sleep, :sync, :use_real_time, :tick, :look, :midi_cc, :midi_sysex, :sample, :buffer, :live_audio, :with_fx, :cue, :time_warp, :puts)
sonic_pi = SonicPiWrapper.new(method(:in_thread), method(:loop), method(:live_loop), method(:use_bpm), method(:sleep), method(:sync), method(:use_real_time), method(:tick), method(:look), method(:midi_cc), method(:midi_sysex), method(:sample), buffer, method(:live_audio), method(:with_fx), method(:cue), method(:time_warp), method(:puts))

require '~/whyjustin/sonic-push/ableton-push.rb'
require '~/whyjustin/sonic-push/clock.rb'
require '~/whyjustin/sonic-push/drum-machine.rb'
require '~/whyjustin/sonic-push/session-machine.rb'
require '~/whyjustin/sonic-push/mode-switcher.rb'

push = AbletonPush.new(sonic_pi)

drum_machine = DrumMachine.new(sonic_pi, push)
sampler = Sampler.new(sonic_pi, push)
session_machine = SessionMachine.new(sonic_pi, push, sampler)
metronome = Clock.new(sonic_pi, push)

ModeSwitcher.new(sonic_pi, push, session_machine, drum_machine)
