

// Would need to change so input device is microphone input/audio interface, as desired

/* s.boot;
ServerOptions.devices;
s.options.inDevice_("MacBook Pro Microphone");
s.options.outDevice_("MacBook Pro Speakers");
s.options.outDevice_("External Headphones");*/

// BEWARE: this program expects MIC input so if you don't have headponhes or a mic setup will probably feedback horrifically!


// buses for routing signals to various effects/outs

(

s.waitForBoot {


// Buffers that contain various samples of playing that get used during piece

var liveRecord = false; // if true, code expects performer to play live, if false plays back some prerecorded ideas
// as sample

var mainBuf = Buffer.alloc(s, s.sampleRate*35,1);
var liveBuf = Buffer.alloc(s,s.sampleRate*3);

var kalimbaPath = thisProcess.nowExecutingPath.dirname +/+ "/CT_132_kalimba_loop_meditate_Bmaj.wav";
var heldPath = thisProcess.nowExecutingPath.dirname +/+ "/ideas 3.aif";
var ideasPath = thisProcess.nowExecutingPath.dirname +/+ "/ideas 1.aif";

var kalimbaBuf =  Buffer.readChannel(s,kalimbaPath,channels:[0]); // kalimba sample for granular soundscape section from Splice.com

var heldABuf =  Buffer.readChannel(s,heldPath,channels:[0]);
var ideasBuf = Buffer.readChannel(s,ideasPath,channels:[0]);


// Following code is adapted from my own Homework 5 for using automata to generate polytonal chord progressions:

// ranks polytonal chords where C is bass triad and upper chord represented by indice 0-12 is upper
// lower positions in list indicate less resonant, resonance increases as list goes on
// this is determined by my own ears in conjuction with Persichetti's chapter on polychords in his book "20th Century Harmony"
var majMajResonanceScores = [0,1,7,5,3,8,10,2,9,6,4,11];
// ranking for C major triad in bass and minor triad above
var majMinResonanceScores = [7,2,9,1,5,8,10,0,3,4,6,11,];

// circle of fifths for use in scoring function later
var circleOfFifths = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5];
// I choose to omit min-min polychords because I personally do not care much for the sound but that is an arbitrary and purely compositional choice

// keep arrays of possible voicings
var inputs;

// chordal duration, change to effect how long each chord is held
var duration = 4;

// scale values into some range for use in scoring function
var scaleValues = {
		arg listToScale,minVal=0,maxVal=10;

		// Calculate the scaling factors
		var scaleFactor = maxVal / (listToScale.maxItem - listToScale.minItem);

		var squeezedList = listToScale.collect { |value|
    (value - listToScale.minItem) * scaleFactor + minVal;
};

	squeezedList;
	};


var normalizeListProbDist = { |list|
    var sum = list.sum;
    list.collect { |value| value / sum };
};

// calculate how far apart two keys are on the circle of fifths
var circleOfFifthsDifference = {
		arg key1,key2;

		// min because you can go either left or right on circle of fifths
		min((circleOfFifths.indexOf(key1)-circleOfFifths.indexOf(key2)) % circleOfFifths.size,
		(circleOfFifths.indexOf(key2)-circleOfFifths.indexOf(key1)).abs) % circleOfFifths.size;
	};
// take input of chords that are more or less resonant than current, calculate distance in circle of fifths and score and rank all possible chords
var scoreChords = {
		arg possibleChords,inputSymbol,currentUpperStructure;

		var positionScores,totalScores;
		// multiplicative weight for determing how much difference in circle of fifths accounts for choice
		var lambda = 2;

		if (inputSymbol == \increase_resonance)
		{
			positionScores = possibleChords.collect({arg item, i; i});
			positionScores = scaleValues.value(positionScores,0,10);

			totalScores = positionScores.collect(
				{
					arg item,i;
					item+(lambda*circleOfFifthsDifference.value(currentUpperStructure[0],possibleChords.at(i)));
			});
		}
		{
			// if decreasing in resonance position scores are reversed
			positionScores = possibleChords.collect({arg item, i; i});
			positionScores = positionScores.reverse;
			positionScores = scaleValues.value(positionScores,0,10);

			totalScores = positionScores.collect(
				{
					arg item,i;
					item+(lambda*circleOfFifthsDifference.value(currentUpperStructure[0],possibleChords.at(i)));
			});

		};

		totalScores;
	};


// This function chooses the next polytonal chord state to move to given the following considerations:
// polytonal chords have a certain amount of resonance (see: the works of Messiaen and Vincent Persichetti)
// we choose a chord state that either is more or less resonant than the current weighted by the following bonus considerations to make progression smoother:
// we prioritize:
// smaller root movements in both voices and
	// chords that are closer in the circle of fifths to make movemenets less jarring (ie prefer C->D rather than C->F#)
// after scoring chords, we sample probability and choose next state
var chooseNext = { arg currentUpperStructure, inputSymbol;

		var indexOfCurr;
		var possibleChords;
		var scores;
		var majorFlag;

		// final state is when we try and decrease resonance with a C/C chord
		if((inputSymbol == \decrease_resonance) && (currentUpperStructure[0] == 0))
		{\END}
		{
		// choose randomally whether to state change to a maj-min or maj-maj chord
		if ([0,1].choose == 0) {
				majorFlag = \major;
				indexOfCurr = majMajResonanceScores.indexOf(currentUpperStructure[0]);
			// get all chords more or less resonant than current
			  if(inputSymbol == \increase_resonance) {
				possibleChords = majMajResonanceScores[(indexOfCurr+1)..(majMajResonanceScores.size-1)];
			    }
			{possibleChords = majMajResonanceScores[0..(indexOfCurr-1)];};

			}
			{
				majorFlag = \minor;
				indexOfCurr = majMinResonanceScores.indexOf(currentUpperStructure[0]);
			  if(inputSymbol == \increase_resonance) {
				possibleChords = majMinResonanceScores[(indexOfCurr+1)..(majMinResonanceScores.size-1)];
			    }
			{	possibleChords = majMinResonanceScores[0..(indexOfCurr-1)]};


		};
		// calculate resonance scores as function of possible chords and their positions

		scores = scoreChords.value(possibleChords,inputSymbol,currentUpperStructure);
		scores = normalizeListProbDist.value(scores);

		// choose chord output weighted by scores calculated above
		[possibleChords.wchoose(scores),majorFlag];
	}};


// represent Mealy Machine (~mm) as event
	~mm = (in: \increase_resonance, state: [0,\major],
	process_state: {
		case
		// if input == \increase_resonance, score and choose a more resonant polytonal chord state to transition to and output voicing of current state
		{(~mm.in == \increase_resonance)} { ~mm.state = chooseNext.value(~mm.state,~mm.in)}
		// opposite for \decrease_resonance
		{(~mm.in == \decrease_resonance)} {~mm.state = chooseNext.value(~mm.state,~mm.in)}
		// default : if input not recognized
	    { "Invalid Input".warn;};}

);


// this function granulates main buffer from beginning of piece with flexbility over how much to corrupt it
// a "memory" is a term I'm using for a statement of previously played material repeated back and layered in some way
~granulateMemories = {
	arg buf,numMemories=1,rate=1,out=0,grainDur=0.5,panRand=0.0,panHz=0.2,sus=5,amp=0.5;
	var startPos,endPos;

	numMemories.do({
		startPos = 0.rrand(1.0);
		endPos = 0.rrand(1.0);

		Synth(\grainbuf, [\buf,buf,\out,out,\sus,sus,\amp,0.2,\startPos,startPos,\endPos,endPos,\rate,rate,\panRand,panRand,\panHz,panHz,\dur,grainDur,\amp,amp])});

};

s.sync;

// --- SynthDefs and other asynchronous stuff ---

// basic large reverb
SynthDef(\reverb,{
	var sig, wet;
	sig = In.ar(\in.ir(0),2);
	wet = GVerb.ar(sig.sum,250,4);
	wet = LPF.ar(wet,1000);
	sig = sig.blend(wet,\mix.kr(0.2));
	Out.ar(\out.ir(0),sig);

}).add;


// next three synths are for recording a mic signal and writing it into a buffer
SynthDef.new(\mic, {
	arg in=0, out=0, amp=1;
	var sig;
	sig = SoundIn.ar(in)*amp;
	Out.ar(out,sig);
	}).add;


SynthDef.new(\ptr, {
	arg out = 0, buf = 0;
	var sig;
	sig = (Line.ar(0,BufSamples.ir(buf),BufDur.ir(buf),doneAction:2));
	Out.ar(out,sig);
}).add;

SynthDef.new(\rec, {
	arg ptrIn=0, micIn=0, buf=0;
	var ptr,sig;
	ptr = In.ar(ptrIn,1);
	sig = In.ar(micIn,1);
	BufWr.ar(sig,buf,ptr);
}).add;

// for using granular synthesis on live signal which is used in several modules
SynthDef(\tgrains_live, {
	var sig, env,mic, ptr, pos, buf = \buf.kr(0), ptrRate = 1;
	env = Env.asr(\atk.ir(0.1), \sus.ir(1),\rel.ir(1)).kr(2,\gate.kr(1));
	mic = SoundIn.ar(0);
	ptr = Phasor.ar(0,1,BufFrames.kr(buf));
	BufWr.ar(mic,buf,ptr);

	pos =  ((ptr/SampleRate.ir)-1.5) % (BufDur.kr(buf));
	pos = pos + LFNoise1.kr(100).bipolar(0.2);

	sig = TGrains.ar(
		numChannels:2,
		trigger:Dust.kr(10),
		bufnum: buf,
		rate:\rate.kr(1),
		centerPos:pos,
		dur:0.1,
		pan:0,
		amp:1
	);
	sig = sig * env * \amp.kr(0.2);
	sig = sig+mic;
	//sig = sig.blend(mic,0.5);

Out.ar(\out.kr(0),sig);
}).add;

SynthDef(\grainbuf, {

	arg startPos, endPos,totalDur,dur=0.5,panHz=0.1,panRand=0.7;
	var sig, env, panPos;
	env = Env([0,1,1,0], [\atk.ir(1),\sus.ir(4),\rel.ir(1)],[1,0,-1]).kr(2);

	// set pan to either down the center or random via LFNoise
	panPos = 0+LFNoise1.kr(panHz).bipolar(panRand);
	sig = GrainBuf.ar(
		numChannels:2,
		trigger:Dust.kr(10),
		dur:dur,
		sndbuf:\buf.kr(0),
		rate:\rate.kr(1),
		pos:Line.kr(startPos,endPos,BufDur.kr(\buf.kr(0))*(endPos-startPos)),
		interp:2,
		pan:panPos,
		envbufnum:-1
	);
sig = sig * env * \amp.kr(0.5);
Out.ar(\out.kr(0),sig);
}).add;


// Harmonizer synth -> adapted from code from Professor Petersen from the Machine Listening Class
SynthDef(\harmonizer,{
var pitches = [7.midiratio,4.midiratio,12.midiratio];
var in = SoundIn.ar(0);
var amp = 0.6;
var sig;
	var chain = FFT(LocalBuf(512), in);
	var trig = Onsets.kr(chain, 0.5); // change to 0.5 for buffer c or d
	var p1 = Demand.kr(trig, 0, Drand(pitches, inf));
	var p2 = Demand.kr(trig, 0, Drand(pitches, inf));
	var p3 = Demand.kr(trig, 0, Drand(pitches, inf));

	var harm1 = PitchShift.ar(
        in,    // stereo audio input
        0.1,             // grain size
        p1,    // pitch ratio
        0,                 // pitch dispersion
        0.004            // time dispersion
    );

	var harm2 = PitchShift.ar(
        in,    // stereo audio input
        0.1,             // grain size
        p2,    // pitch ratio
        0,                 // pitch dispersion
        0.004            // time dispersion
    );

	var harm3 = PitchShift.ar(
        in,    // stereo audio input
        0.1,             // grain size
        p3,    // pitch ratio
        0,                 // pitch dispersion
        0.004            // time dispersion
    );

	//trig.poll;

	sig = (in + harm1 + harm2 + harm3)*amp;
	Out.ar(0,sig);
}).add;

// Large Delay/Reverb Effect - adapted from Eli Fieldsteel's SuperCollider tutorials
SynthDef(\infiniteHoldReverb, {

	arg feedback=1;
	var sig, local;

	sig = SoundIn.ar(0);
	local = LocalIn.ar(2)+sig.dup;

	15.do{local=AllpassN.ar(local,0.06,Rand(0.001,1),3)};

	LocalOut.ar(local*feedback);

	Out.ar(0,sig+local);
}).add;


/* --- Pattern classes to play your music --- */

// groups for keeping signals organized
~micGrp = Group.new;
~ptrGrp = Group.after(~micGrp);
~recGrp = Group.after(~ptrGrp);
~granGrp = Group.after(~micGrp);


~micBus = Bus.audio(s,1);
~ptrBus = Bus.audio(s,1);


// Code for having synths triggered on space bar presses adapted from code provided to me by Professor Petersen
t = 0;
i = 0;
w = Window.new("Modules");
w.view.keyDownAction = {
	arg view, char, modifiers, unicode, keycode;
	var mic, ptr, rec, synth;

	var rbus = Bus.audio(s,2);
	ServerTree.add({Synth(\reverb,[\in,rbus])});
	if (liveRecord){}{mainBuf=ideasBuf};

	i = i + 1;
	("Mpdule " ++ i).postln;

	case
	// First press
	{ t == 0 && (keycode == 49) }
	{
		// Module 1: record live signal which gets processed later on
		// ~35 seconds
		("RECORDING ").postln;
		if(liveRecord)
		{
		mic = Synth(\mic, [\in, 0,\out, ~micBus],~micGrp);
		ptr = Synth(\ptr, [\buf,mainBuf,\out, ~ptrBus],~ptrGrp);
		rec = Synth(\rec, [\ptrIn, ~ptrBus, \micIn, ~micBus,\buf,mainBuf],~recGrp);
		}{};
		t = t + 1;
	}
	// Second press
	{ t == 1 && (keycode == 49) }
	{
		mic.free;
		ptr.free;
		rec.free;
		// Module 2: signal is granulated live based on mic input
		// continues until spacebar is pressed
		"GRANULATING LIVE SIGNAL".postln;
		synth = Synth(\tgrains_live, [\buf,liveBuf,\out,0,\rel,5,\sus,3]);
		t = t + 1;
	}
	{ t == 2 && (keycode == 49) }
	{
		synth.free;
		// Module 3: first "memory" - what was recorded in module 1 is now granulated and played back as performer
		// continues to improvise
		"PLAYING WHAT WAS RECORDED IN MODULE 1".postln;
		{
		if(liveRecord){6.do({
					arg i;
			~granulateMemories.value(mainBuf,numMemories:1,rate:1,out:0,panRand:1,grainDur:0.7.rrand(1.0),amp:0.1);
			(3.rrand(9)).wait;
				});}
		{
				6.do({
					arg i;
			~granulateMemories.value(mainBuf,numMemories:1,rate:1,out:0,panRand:1,grainDur:0.7.rrand(1.0),amp:0.1);
			(3.rrand(9)).wait;
				});
		}
		}.fork();
		t = t + 1;
	}
	{ t == 3 && (keycode == 49) }
	{

		// Module 4: harmonizer effect on live signal
		// continues until spacebar is pressed again
		"HARMONIZER".postln;
		synth = Synth(\harmonizer);
		t = t + 1;
	}
	{ t == 4 && (keycode == 49) }
	{
		// Module 5: granular synthesis soundscape with reversed kalimba sample and automata polytonal chord progression and memories once again, but more corrupted than before
		// collect final output progression
		var finalOutputs = [[0, \major]];
		var inputs = Array.fill(8.rand,{\increase_resonance})++\decrease_resonance;
		synth.free;

inputs.do(
		{
			arg item,i;
			~mm.in = item;
			~mm.process_state;
			finalOutputs = finalOutputs.add(~mm.state);
		};
	);

// if we haven't ended, continue to decrease resonance until we find ourselves in final state
while {~mm.state != \END}
{~mm.process_state;finalOutputs = finalOutputs.add(~mm.state);}{};

// play chords
"polytonal progression".postln;
finalOutputs.postln;
		// if final progression is too short, double it
		if (finalOutputs.size < 4) {finalOutputs = finalOutputs[0..(finalOutputs.size-2)] ++ finalOutputs;}{};
		// if still too short to be useful, add randomly generated chords
		if (finalOutputs.size < 4) {finalOutputs ++ [0.rrand(12),\major;]}{};

		{
			if(liveRecord){} {2.wait; Synth(\mic, [\in, 0,\out, 0]);};
		}.fork();
{

finalOutputs.do {
	arg chords,i;
	chords.postln;
	if (chords != \END)
		{
			var startPos = 0.rrand(1);
			var endPos = 0.rrand(1);
		var granularSynth = Synth(\grainbuf, [\buf,kalimbaBuf,\out,rbus,\amp,0.05,\sus,8,\startPos,startPos,\endPos,endPos,\rate,((chords[0]+1).midiratio)*(-1)]);
		var duration = 6;
		duration.wait;
	}

};
}.fork();

		{
		4.do {
				~granulateMemories.value(mainBuf,numMemories:3,rate:1,out:0,panRand:1,grainDur:0.4.rrand(0.7),amp:0.1);
		5.wait;
		}
		}.fork();
		"REVERSE GRANULAR SOUNDSCAPE+MEMORIES...".postln;
		t = t + 1
	}
	{ t == 5 && (keycode == 49) }
	{
		// Module 6: held note is granulated, giving illusion of it being sustained forever
		// on top of this, more memories and improvisation
		("INFINITELY HELD GRANULATED NOTE + MORE FRAGMENTED MEMORIES " ++ t).postln;
		{
		3.wait;
		// this buffer contains a prerecorded held note which gets granulated in this section
			Synth(\grainbuf, [\buf,heldABuf,\out,rbus,\sus,30,\amp,0.2,\startPos,0.2,\endPos,0.2,\rate,1,\amp,0.1]);
			3.do {
			~granulateMemories.value(mainBuf,numMemories:5,rate:1,out:0,panRand:1,grainDur:0.2.rrand(0.5),amp:0.1);
			5.wait;
			}
		}.fork();
		t = t+1;
	}
	{ t == 6 && (keycode == 49) }
	{
		// Module 7: Final module. Most corrupted memories appear in conjuction with infinite delay effect
		// everything slowly dies away as performer continues and is eventually left alone
		{
		synth = Synth(\infiniteHoldReverb,[\feedback,0.55]);

		{
		3.do {
				~granulateMemories.value(mainBuf,numMemories:1,rate:1,out:0,panRand:1,grainDur:0.1.rrand(0.2),amp:0.1);
		5.wait;
		}
		}.fork();

		synth.set(\feedback,0.3);
		3.wait;

		3.do {
				~granulateMemories.value(mainBuf,numMemories:1,rate:1,out:0,panRand:1,grainDur:0.1.rrand(0.15),amp:0.07);
		3.wait;
		};

		10.wait;

		z.free;

		3.do {
				~granulateMemories.value(mainBuf,numMemories:1,rate:1,out:0,panRand:1,grainDur:0.1.rrand(0.12),amp:0.05);
		3.wait;
		}
		}.fork();

		synth.set(\feedback,0.1);

		"LAST MODULE: MEMORIES+REVERB".postln;
		t = t+1;
	}
	{ t == 7 && (keycode == 49) }
	{
		("Spacebar round " ++ t).postln;
		"ENDING".postln;
		t = nil;
		w.close;
		synth.free;
	}
	;
};
w.front;
};

)

/*
s.record;
s.stopRecording*/