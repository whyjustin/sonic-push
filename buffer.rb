use_debug false
SonicPiWrapper = Struct.new(:in_thread, :loop, :live_loop, :use_bpm, :sleep, :sync, :use_real_time, :tick, :look, :midi_cc, :midi_sysex, :sample, :buffer, :live_audio, :with_fx, :cue, :time_warp, :puts, :with_swing, :control, :set_mixer_control, :sample_duration, :osc_send, :midi_clock_beat, :use_synth, :play, :midi, :get_event, :get, :set, :current_sched_ahead_time)
sonic_pi = SonicPiWrapper.new(method(:in_thread), method(:loop), method(:live_loop), method(:use_bpm), method(:sleep), method(:sync), method(:use_real_time), method(:tick), method(:look), method(:midi_cc), method(:midi_sysex), method(:sample), buffer, method(:live_audio), method(:with_fx), method(:cue), method(:time_warp), method(:puts), method(:with_swing), method(:control), method(:set_mixer_control!), method(:sample_duration), method(:osc_send), method(:midi_clock_beat), method(:use_synth), method(:play), method(:midi), method(:get_event), get, method(:set), current_sched_ahead_time)

require '/home/pi/sonic-push/sonic-push-requires.rb'

# load '/home/pi/sonic-push/module.rb'

# Latency in seconds
SessionMachine.latency = 0.19
SessionMachine.recording_pre_amp = 8.0
SessionMachine.mute_while_recording = true

push = AbletonPush.new(sonic_pi)

drum_machine = DrumMachine.new(sonic_pi, push)
chop_sampler = ChopSampler.new(sonic_pi, push)
sampler = Sampler.new(sonic_pi, push)
synth = Synthesizer.new(sonic_pi, push)
session_machine = SessionMachine.new(sonic_pi, push, sampler, chop_sampler, drum_machine, synth)
metronome = Clock.new(sonic_pi, push)

session_machine.set_save_location '/home/pi/'

drum_machine.load_kit '/home/pi/sonic-push/kits/808-kick-snare-clap'
drum_machine.load_kit '/home/pi/sonic-push/kits/808-toms'
drum_machine.load_kit '/home/pi/sonic-push/kits/808-congas'
drum_machine.load_kit '/home/pi/sonic-push/kits/808-rim-clav-mara-cow-hats'
drum_machine.load_kit '/home/pi/sonic-push/kits/linn-kick-scare-tom-ride-tam'
drum_machine.load_kit '/home/pi/sonic-push/kits/linn-conga-hat-cowbell-clap-cab'
drum_machine.load_kit '/home/pi/sonic-push/kits/dmx-kick-snare-tom'
drum_machine.load_kit '/home/pi/sonic-push/kits/dmx-ride-tam-hat-clap-stick-crash-shake'

drum_machine.load_kit [
  :bd_808,
  :sn_dub,
  :elec_fuzz_tom,
  :bd_sone,
  :bd_haus,
  :elec_filt_snare,
  :perc_snap,
  :vinyl_scratch
]

drum_machine.load_kit '/home/pi/sonic-push/kits/stabs'

synth.load_synth :piano
synth.load_synth 'deepmind12_midi_1'
synth.load_synth 'op-1_midi_device_midi_1'
