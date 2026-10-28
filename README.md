# DTMF Tone Generator & FFT Decoder

![MATLAB](https://img.shields.io/badge/MATLAB-R2021a%2B-orange)
![No toolbox needed](https://img.shields.io/badge/Toolboxes-none-brightgreen)
![ITU-T Q.23](https://img.shields.io/badge/ITU--T-Q.23-blue)

A MATLAB App Designer project that generates DTMF (telephone keypad) tones, adds noise to them, and decodes them back using the FFT. It can decode tones from the on-screen keypad, an uploaded audio file, or a live microphone recording.

Built for **Digital Signal Processing (ECN15101)**, Group 4, Department of ECE, MNNIT Allahabad.


## What it does

Every key on a phone keypad sends two sine tones at once, one from a row frequency and one from a column frequency. By finding those two frequencies, a receiver can tell which key was pressed. This app does the whole job in one window:

- Generates all 16 keys (0-9, A-D, `*`, `#`)
- Adds AWGN noise with an SNR you control (0 to 30 dB)
- Decodes the noisy tone with a Hann-windowed 2048-point FFT
- Rejects weak or doubtful signals and shows `?` instead of a wrong digit
- Plots the waveform and the spectrum live, with the detected peaks marked
- Logs every keypress in a history table
- Decodes a whole **audio file** and lists the keys in order
- Decodes tones played from another device through the **microphone**

It only uses base MATLAB, so no extra toolbox is needed.

## Running it

You need MATLAB R2021a or later. Clone the repo, open the folder in MATLAB and run:

```matlab
DTMF_App_updated
```

## Using it

**Keypad:** set the SNR slider, then press a key. The app plays the tone, decodes it and updates the plots and history.

**Audio file:** click *Upload audio file* and pick a DTMF recording. All detected keys appear in order, for example `91240*32`. Tones should be around 100 ms or longer with short pauses between them.

**Microphone:** choose a recording length, click *Record* and play the tones from a phone or speaker near the mic.

## How the decoding works

1. Remove the DC offset and apply a Hann window to the frame.
2. Take a 2048-point FFT (the 800-sample frame is zero-padded).
3. Find the strongest peak in the low band (600-1000 Hz) and the high band (1200-1700 Hz).
4. Match each peak to the nearest standard DTMF frequency to get the key.
5. Check the result against four rules. If any fails, the output is `?`.

| Rule | Limit |
|---|---|
| Frequency error | within 1.5% of the standard frequency |
| Peak strength | at least 14 dB above the median noise |
| Twist | low and high tones within 6 dB of each other |
| Channel SNR | 10 dB or higher |

The 10 dB limit is set by `MinimumDecodeSNR` and can be changed.

| Row \ Column | 1209 Hz | 1336 Hz | 1477 Hz | 1633 Hz |
|:---:|:---:|:---:|:---:|:---:|
| **697 Hz** | 1 | 2 | 3 | A |
| **770 Hz** | 4 | 5 | 6 | B |
| **852 Hz** | 7 | 8 | 9 | C |
| **941 Hz** | * | 0 | # | D |

Settings used: 8 kHz sampling, 100 ms frames (800 samples), 3.90625 Hz FFT bin spacing.

## Results

We sent each of the 16 keys 50 times at different SNR values (800 trials per SNR).

| SNR (dB) | Correct by peak picking | Accepted after quality checks |
|:---:|:---:|:---:|
| -15 | 49.4% | 0.0% |
| -12 | 84.5% | 0.4% |
| -10 | 96.8% | 6.1% |
| -8 | 100% | 39.8% |
| -5 | 100% | 98.4% |
| 0 to 30 | 100% | 100% |

Decoding stays accurate even when the noise is stronger than the tones, and the quality checks only start rejecting keys at around -8 dB. Both the audio file and microphone decoders recovered the test sequence `91240*32` correctly.


## Future work

- Goertzel algorithm instead of a full FFT
- Continuous microphone decoding for long digit sequences
- More channel effects (fading, echo, speech interference)
- Exporting results to CSV/Excel
- Porting the decoder to a microcontroller or DSP board

## Team

| Name | GitHub |
|---|---|
| Devansh Bajpai | [@devansh-bajpai](https://github.com/devansh-bajpai) |
| Dharavath Nithin | [@nithin10105](https://github.com/nithin10105) |
| Dharavathu Kushwanth Nayak | [@kushwanth-117](https://github.com/kushwanth-117) |
| Dhruv Mishra | [@Dhruvgit19](https://github.com/Dhruvgit19) |
