classdef DTMF_App < matlab.apps.AppBase
    % 16-key DTMF generator, AWGN channel and FFT decoder.
    % Each keypress generates and decodes one 100 ms frame.

    properties (Access = public)
        UIFigure
        TimeAxes
        SpectrumAxes
        SNRSlider
        SNRValueLabel
        MeasuredSNRLabel
        PressedLabel
        DecodedLabel
        SequenceField
        LogTable
        StatusLabel
        AudioStatusLabel
        AudioCheckBox
        ReplayButton
    end

    properties (Constant, Access = private)
        Fs = 8000
        ToneDuration = 0.1
        NFFT = 2048
        LowFrequencies = [697 770 852 941]
        HighFrequencies = [1209 1336 1477 1633]
        KeyMap = ['1' '2' '3' 'A'; ...
                  '4' '5' '6' 'B'; ...
                  '7' '8' '9' 'C'; ...
                  '*' '0' '#' 'D']
    end

    properties (Access = private)
        Time = []
        CleanTone = []
        UnitNoise = []
        ReceivedTone = []
        CurrentKey = ''
        DecodedSequence = ''
        History = cell(0, 7)
        MainGrid
        ActiveButton = []
        CleanLine
        ReceivedLine
        SpectrumLine
        PeakMarkers
        PeakStems
        LowPeakText
        HighPeakText
    end