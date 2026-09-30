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

            label = uilabel(cg, 'Text', 'CHANNEL SNR', ...
                'FontWeight', 'bold', 'FontColor', ink);
            label.Layout.Row = 4;
            label.Layout.Column = 1;

            app.SNRValueLabel = uilabel(cg, 'Text', '20.0 dB', ...
                'HorizontalAlignment', 'right', 'FontWeight', 'bold', ...
                'FontColor', [0.12 0.40 0.78]);
            app.SNRValueLabel.Layout.Row = 4;
            app.SNRValueLabel.Layout.Column = 2;

            app.SNRSlider = uislider(cg, 'Limits', [0 30], 'Value', 20, ...
                'MajorTicks', 0:5:30, 'MinorTicks', [], 'FontColor', ink);
            app.SNRSlider.Layout.Row = 5;
            app.SNRSlider.Layout.Column = [1 2];
            app.SNRSlider.Tooltip = ...
                'Drag to re-analyze the current tone. Replay to hear it.';

            app.SNRSlider.ValueChangingFcn = ...
                @(~,event) app.snrChanged(event.Value);
            app.SNRSlider.ValueChangedFcn = ...
                @(~,event) app.snrChanged(event.Value);

            app.MeasuredSNRLabel = uilabel(cg, ...
                'Text', 'Measured SNR: -- dB', 'FontColor', muted);
            app.MeasuredSNRLabel.Layout.Row = 6;
            app.MeasuredSNRLabel.Layout.Column = [1 2];

            app.AudioCheckBox = uicheckbox(cg, 'Text', 'Play audio', ...
                'Value', true, 'FontColor', ink, ...
                'ValueChangedFcn', @(~,~) app.audioChanged());
            app.AudioCheckBox.Layout.Row = 7;
            app.AudioCheckBox.Layout.Column = 1;

            app.ReplayButton = uibutton(cg, 'push', 'Text', 'Replay tone', ...
                'Enable', 'off', 'BackgroundColor', background, ...
                'FontColor', ink, 'ButtonPushedFcn', @(~,~) app.playTone());
            app.ReplayButton.Layout.Row = 7;
            app.ReplayButton.Layout.Column = 2;

            plots = uipanel(body, 'Title', 'SIGNAL ANALYSIS', ...
                'FontWeight', 'bold', 'BackgroundColor', navy, ...
                'ForegroundColor', light);
            plots.Layout.Column = 2;

            pg = uigridlayout(plots, [2 1]);
            pg.RowHeight = {'1x', '1x'};
            pg.BackgroundColor = navy;
            pg.Padding = [12 8 12 10];
            pg.RowSpacing = 14;

            app.TimeAxes = uiaxes(pg);
            app.TimeAxes.Layout.Row = 1;
            app.SpectrumAxes = uiaxes(pg);
            app.SpectrumAxes.Layout.Row = 2;

            for ax = [app.TimeAxes app.SpectrumAxes]
                ax.Color = navy;
                ax.XColor = light;
                ax.YColor = light;
                ax.GridColor = [0.50 0.60 0.72];
                ax.GridAlpha = 0.20;
                ax.FontSize = 11;
                ax.Box = 'off';
                ax.XGrid = 'on';
                ax.YGrid = 'on';
                ax.Title.Color = light;
                ax.XLabel.Color = light;
                ax.YLabel.Color = light;
                hold(ax, 'on');
            end

            app.CleanLine = plot(app.TimeAxes, NaN, NaN, '--', ...
                'Color', [0.62 0.70 0.80], 'LineWidth', 1);
            app.ReceivedLine = plot(app.TimeAxes, NaN, NaN, ...
                'Color', blue, 'LineWidth', 1);

            title(app.TimeAxes, 'Time domain - press a key');
            xlabel(app.TimeAxes, 'Time (ms)');
            ylabel(app.TimeAxes, 'Amplitude');
            xlim(app.TimeAxes, [0 100]);
            ylim(app.TimeAxes, [-2.5 2.5]);

            legend(app.TimeAxes, [app.CleanLine app.ReceivedLine], ...
                {'Clean composite', 'Received (AWGN)'}, ...
                'Location', 'northeast', 'Orientation', 'horizontal', ...
                'TextColor', light, 'Color', navy, 'EdgeColor', navy, ...
                'AutoUpdate', 'off');

            app.SpectrumLine = plot(app.SpectrumAxes, NaN, NaN, ...
                'Color', blue, 'LineWidth', 1.3);

            app.PeakStems = plot(app.SpectrumAxes, NaN, NaN, '--', ...
                'Color', red, 'LineWidth', 1);

            app.PeakMarkers = plot(app.SpectrumAxes, NaN, NaN, 'v', ...
                'Color', red, 'MarkerFaceColor', red, ...
                'MarkerSize', 8, 'LineStyle', 'none');

            app.LowPeakText = text(app.SpectrumAxes, NaN, NaN, '', ...
                'Color', red, 'FontWeight', 'bold', 'FontSize', 10, ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom');

            app.HighPeakText = text(app.SpectrumAxes, NaN, NaN, '', ...
                'Color', red, 'FontWeight', 'bold', 'FontSize', 10, ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom');

            title(app.SpectrumAxes, 'Single-sided FFT magnitude');
            xlabel(app.SpectrumAxes, 'Frequency (Hz)');
            ylabel(app.SpectrumAxes, 'Magnitude');
            xlim(app.SpectrumAxes, [0 2000]);
            ylim(app.SpectrumAxes, [0 1.4]);

            historyPanel = uipanel(root, 'Title', 'DECODED HISTORY', ...
                'FontWeight', 'bold', 'ForegroundColor', ink, ...
                'BackgroundColor', [1 1 1]);
            historyPanel.Layout.Row = 3;

            hg = uigridlayout(historyPanel, [2 3]);
            hg.RowHeight = {28, '1x'};
            hg.ColumnWidth = {140, '1x', 110};
            hg.Padding = [10 8 10 8];
            hg.BackgroundColor = [1 1 1];

            label = uilabel(hg, 'Text', 'Decoded sequence', ...
                'FontColor', ink);
            label.Layout.Row = 1;
            label.Layout.Column = 1;

            app.SequenceField = uieditfield(hg, 'text', 'Editable', 'off', ...
                'FontName', 'Consolas', 'FontSize', 16, ...
                'FontColor', ink, 'BackgroundColor', background);
            app.SequenceField.Layout.Row = 1;
            app.SequenceField.Layout.Column = 2;
            app.SequenceField.Tooltip = ...
                'Keypress results; ? means uncertain. Latest 200 keys retained.';

            clearButton = uibutton(hg, 'push', 'Text', 'Clear history', ...
                'BackgroundColor', background, 'FontColor', ink, ...
                'ButtonPushedFcn', @(~,~) app.clearHistory());
            clearButton.Layout.Row = 1;
            clearButton.Layout.Column = 3;

            app.LogTable = uitable(hg, 'Data', app.History, ...
                'ColumnName', {'Time', 'Pressed', 'Decoded', 'SNR (dB)', ...
                               'Low (Hz)', 'High (Hz)', 'Result'}, ...
                'ColumnWidth', {85, 70, 70, 85, 90, 90, 'auto'}, ...
                'ColumnEditable', false(1,7), 'RowName', [], ...
                'FontSize', 11, 'ForegroundColor', ink, ...
                'BackgroundColor', [1 1 1; background]);
            app.LogTable.Layout.Row = 2;
            app.LogTable.Layout.Column = [1 3];
            app.LogTable.Tooltip = ...
                'Newest first. SNR is the requested channel SNR. Latest 100 rows retained.';

            footer = uigridlayout(root, [1 2]);
            footer.Layout.Row = 4;
            footer.ColumnWidth = {'1x', 150};
            footer.Padding = [0 0 0 0];
            footer.BackgroundColor = background;

            app.StatusLabel = uilabel(footer, ...
                'Text', 'Ready. Press a keypad button to generate and decode a tone.', ...
                'FontColor', muted, 'FontSize', 12);

            app.AudioStatusLabel = uilabel(footer, 'Text', 'Audio enabled', ...
                'HorizontalAlignment', 'right', 'FontColor', muted);

            app.UIFigure.SizeChangedFcn = @(~,~) app.resizeLayout();
            app.resizeLayout();
        end