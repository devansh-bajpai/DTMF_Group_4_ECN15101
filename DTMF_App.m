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

    methods (Access = private)
        function createComponents(app)
            background = [0.94 0.96 0.98];
            ink = [0.12 0.18 0.28];
            muted = [0.40 0.46 0.55];
            navy = [0.055 0.085 0.14];
            light = [0.88 0.93 0.98];
            blue = [0.22 0.68 1.00];
            red = [1.00 0.30 0.35];

            screen = get(groot, 'ScreenSize');
            width = min(1220, screen(3)-60);
            height = min(850, screen(4)-100);
            position = [screen(1)+(screen(3)-width)/2, ...
                screen(2)+(screen(4)-height)/2, width, height];

            app.UIFigure = uifigure('Visible', 'off', ...
                'Name', 'DTMF | Tone Generator & FFT Decoder', ...
                'Position', position, 'Color', background, ...
                'AutoResizeChildren', 'off');
            app.UIFigure.CloseRequestFcn = @(~,~) delete(app);

            root = uigridlayout(app.UIFigure, [4 1]);
            app.MainGrid = root;
            root.Scrollable = 'on';
            root.RowHeight = {60, '1x', 160, 24};
            root.ColumnWidth = {'1x'};
            root.Padding = [16 16 16 16];
            root.RowSpacing = 12;
            root.BackgroundColor = background;

            header = uigridlayout(root, [2 1]);
            header.Layout.Row = 1;
            header.RowHeight = {32, 20};
            header.Padding = [0 0 0 0];
            header.RowSpacing = 4;
            header.BackgroundColor = background;

            uilabel(header, 'Text', 'DTMF Tone Generator & FFT Decoder', ...
                'FontSize', 24, 'FontWeight', 'bold', 'FontColor', ink);

            uilabel(header, 'Text', ...
                '8 kHz sampling  |  100 ms tones  |  2048-point FFT  |  3.90625 Hz bin spacing', ...
                'FontSize', 12, 'FontColor', muted);

            body = uigridlayout(root, [1 2]);
            body.Layout.Row = 2;
            body.ColumnWidth = {320, '1x'};
            body.Padding = [0 0 0 0];
            body.ColumnSpacing = 14;
            body.BackgroundColor = background;

            controls = uipanel(body, 'Title', 'KEYPAD & CHANNEL', ...
                'FontWeight', 'bold', 'ForegroundColor', ink, ...
                'BackgroundColor', [1 1 1]);
            controls.Layout.Column = 1;

            cg = uigridlayout(controls, [7 2]);
            cg.RowHeight = {18, 44, '1x', 24, 50, 22, 32};
            cg.ColumnWidth = {'1x', '1x'};
            cg.Padding = [12 12 12 12];
            cg.RowSpacing = 8;
            cg.BackgroundColor = [1 1 1];

            label = uilabel(cg, 'Text', 'PRESSED', 'FontColor', muted);
            label.Layout.Row = 1; label.Layout.Column = 1;

            label = uilabel(cg, 'Text', 'DECODED', 'FontColor', muted);
            label.Layout.Row = 1; label.Layout.Column = 2;

            app.PressedLabel = uilabel(cg, 'Text', '-', 'FontSize', 36, ...
                'FontWeight', 'bold', 'FontColor', ink);
            app.PressedLabel.Layout.Row = 2;
            app.PressedLabel.Layout.Column = 1;

            app.DecodedLabel = uilabel(cg, 'Text', '-', 'FontSize', 36, ...
                'FontWeight', 'bold', 'FontColor', [0.02 0.48 0.35]);
            app.DecodedLabel.Layout.Row = 2;
            app.DecodedLabel.Layout.Column = 2;

            keypad = uigridlayout(cg, [4 4]);
            keypad.Layout.Row = 3;
            keypad.Layout.Column = [1 2];
            keypad.RowHeight = {'1x', '1x', '1x', '1x'};
            keypad.ColumnWidth = {'1x', '1x', '1x', '1x'};
            keypad.Padding = [0 0 0 0];
            keypad.RowSpacing = 8;
            keypad.ColumnSpacing = 8;
            keypad.BackgroundColor = [1 1 1];

            for r = 1:4
                for c = 1:4
                    color = ink;
                    if c == 4
                        color = [0.19 0.32 0.49];
                    end

                    button = uibutton(keypad, 'push', ...
                        'Text', app.KeyMap(r,c), 'FontSize', 24, ...
                        'FontWeight', 'bold', 'FontColor', [1 1 1], ...
                        'BackgroundColor', color, ...
                        'Interruptible', 'off', 'BusyAction', 'queue');

                    button.Layout.Row = r;
                    button.Layout.Column = c;
                    button.UserData = struct('Row', r, 'Column', c, ...
                        'Color', color);

                    button.Tooltip = sprintf('%d Hz + %d Hz', ...
                        app.LowFrequencies(r), app.HighFrequencies(c));

                    button.ButtonPushedFcn = ...
                        @(source,~) app.padButtonPushed(source);
                end
            end