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
        UploadAudioButton
        AudioFileLabel
        FileResultField
        FileStatusLabel
        MicRecordButton
        MicDurationDropDown
        MicResultField
        MicStatusLabel
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
        MicRecorder = []
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

            root = uigridlayout(app.UIFigure, [6 1]);
            app.MainGrid = root;
            root.Scrollable = 'on';
            root.RowHeight = {60, '1x', 160, 180, 150, 24};
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

            filePanel = uipanel(root, 'Title', 'AUDIO FILE DTMF DECODER', ...
                'FontWeight', 'bold', 'ForegroundColor', ink, ...
                'BackgroundColor', [1 1 1]);
            filePanel.Layout.Row = 4;
            fg = uigridlayout(filePanel, [4 2]);
            fg.RowHeight = {32, 32, 22, 22};
            fg.ColumnWidth = {150, '1x'};
            fg.Padding = [10 8 10 8];
            fg.BackgroundColor = [1 1 1];

            app.UploadAudioButton = uibutton(fg, 'push', ...
                'Text', 'Upload audio file', ...
                'Interruptible', 'off', 'BusyAction', 'cancel', ...
                'ButtonPushedFcn', @(~,~) app.uploadAudioFile());
            app.UploadAudioButton.Layout.Row = 1;
            app.UploadAudioButton.Layout.Column = 1;
            app.AudioFileLabel = uilabel(fg, 'Text', 'No file selected', ...
                'Interpreter', 'none', 'FontColor', ink);
            app.AudioFileLabel.Layout.Row = 1;
            app.AudioFileLabel.Layout.Column = 2;
            label = uilabel(fg, 'Text', 'Detection result', 'FontColor', ink);
            label.Layout.Row = 2; label.Layout.Column = 1;
            app.FileResultField = uieditfield(fg, 'text', 'Editable', 'off', ...
                'FontName', 'Consolas', 'FontSize', 16);
            app.FileResultField.Layout.Row = 2;
            app.FileResultField.Layout.Column = 2;
            app.FileStatusLabel = uilabel(fg, 'Text', ...
                'Choose an audio file to detect its DTMF keys.', 'FontColor', muted);
            app.FileStatusLabel.Layout.Row = 3;
            app.FileStatusLabel.Layout.Column = [1 2];
            label = uilabel(fg, 'Text', ...
                'Results list keys in playback order. Use clear tones of about 100 ms or longer, separated by pauses.', ...
                'FontSize', 11, 'FontColor', muted);
            label.Layout.Row = 4; label.Layout.Column = [1 2];

            micPanel = uipanel(root, 'Title', 'MICROPHONE DTMF DECODER', ...
                'FontWeight', 'bold', 'ForegroundColor', ink, ...
                'BackgroundColor', [1 1 1]);
            micPanel.Layout.Row = 5;
            mg = uigridlayout(micPanel, [3 3]);
            mg.RowHeight = {32, 32, 22};
            mg.ColumnWidth = {150, 130, '1x'};
            mg.Padding = [10 8 10 8];
            mg.BackgroundColor = [1 1 1];
            app.MicRecordButton = uibutton(mg, 'push', ...
                'Text', 'Record', ...
                'Interruptible', 'off', 'BusyAction', 'cancel', ...
                'ButtonPushedFcn', @(~,~) app.recordMicrophone());
            app.MicRecordButton.Layout.Row = 1;
            app.MicRecordButton.Layout.Column = 1;
            app.MicDurationDropDown = uidropdown(mg, ...
                'Items', {'5 seconds', '10 seconds', '15 seconds'}, ...
                'ItemsData', [5 10 15], 'Value', 5, ...
                'Tooltip', 'Recording duration');
            app.MicDurationDropDown.Layout.Row = 1;
            app.MicDurationDropDown.Layout.Column = 2;
            app.MicStatusLabel = uilabel(mg, 'Text', ...
                'Ready. Click Record, then play a phone dial-pad tone.', ...
                'FontColor', muted);
            app.MicStatusLabel.Layout.Row = 1;
            app.MicStatusLabel.Layout.Column = 3;
            label = uilabel(mg, 'Text', 'Detection result', 'FontColor', ink);
            label.Layout.Row = 2; label.Layout.Column = 1;
            app.MicResultField = uieditfield(mg, 'text', 'Editable', 'off', ...
                'FontName', 'Consolas', 'FontSize', 16);
            app.MicResultField.Layout.Row = 2;
            app.MicResultField.Layout.Column = [2 3];
            label = uilabel(mg, 'Text', ...
                'Uses the default microphone. Enable phone dial-pad sounds; avoid app playback during recording.', ...
                'FontSize', 11, 'FontColor', muted);
            label.Layout.Row = 3; label.Layout.Column = [1 3];

            footer = uigridlayout(root, [1 2]);
            footer.Layout.Row = 6;
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

        function resizeLayout(app)
            % Preserve usable keypad/plot sizes; scroll on smaller screens.
            position = app.UIFigure.Position;
            bodyHeight = max(470, position(4)-666);
            app.MainGrid.RowHeight = {60, bodyHeight, 160, 180, 150, 24};

            availableWidth = position(3)-32;
            if position(4) < 1136
                availableWidth = availableWidth-20; % Scrollbar space.
            end
            app.MainGrid.ColumnWidth = {max(900, availableWidth)};
        end

        function padButtonPushed(app, button)
            r = button.UserData.Row;
            c = button.UserData.Column;
            app.CurrentKey = app.KeyMap(r,c);
            app.PressedLabel.Text = app.CurrentKey;

            if ~isempty(app.ActiveButton) && isvalid(app.ActiveButton)
                app.ActiveButton.BackgroundColor = ...
                    app.ActiveButton.UserData.Color;
            end
            app.ActiveButton = button;
            button.BackgroundColor = [0.12 0.44 0.85];

            % 1. Synthesis: exactly 800 samples, no duplicate endpoint.
            L = round(app.Fs * app.ToneDuration);
            app.Time = (0:L-1)' / app.Fs;

            app.CleanTone = ...
                sin(2*pi*app.LowFrequencies(r)*app.Time) + ...
                sin(2*pi*app.HighFrequencies(c)*app.Time);

            % Independent unit-variance Gaussian noise per keypress.
            % Reuse this realization during slider motion for comparison.
            app.UnitNoise = randn(L,1);
            result = app.refreshAnalysis(app.SNRSlider.Value);

            % Only keypresses append history.
            % Slider changes and replay never duplicate the sequence.
            app.DecodedSequence = [app.DecodedSequence result.Key];
            app.DecodedSequence = app.DecodedSequence( ...
                max(1, numel(app.DecodedSequence)-199):end);
            app.SequenceField.Value = app.DecodedSequence;

            row = {datestr(now, 'HH:MM:SS'), ...
                app.CurrentKey, result.Key, ...
                round(app.SNRSlider.Value,1), ...
                round(result.PeaksHz(1),1), ...
                round(result.PeaksHz(2),1), result.Reason};

            app.History = [row; app.History];
            app.History = app.History(1:min(100,size(app.History,1)),:);
            app.LogTable.Data = app.History;

            app.ReplayButton.Enable = 'on';
            app.playTone();
        end

        function snrChanged(app, snrDB)
            % event.Value is live even before the mouse is released.
            app.SNRValueLabel.Text = sprintf('%.1f dB', snrDB);

            if ~isempty(app.CleanTone)
                app.refreshAnalysis(snrDB);
            end
        end

        function result = refreshAnalysis(app, snrDB)
            % 2. AWGN: SNR = 10*log10(Psignal/Pnoise).
            % Scale randn by sqrt(Pnoise); no awgn() toolbox dependency.
            signalPower = mean(app.CleanTone.^2);
            noisePower = signalPower / 10^(snrDB/10);
            noise = sqrt(noisePower) * app.UnitNoise;
            app.ReceivedTone = app.CleanTone + noise;

            % Finite-frame measured SNR fluctuates around the target.
            measuredSNR = 10*log10( ...
                signalPower / max(mean(noise.^2), realmin));

            app.SNRValueLabel.Text = sprintf('%.1f dB', snrDB);
            app.MeasuredSNRLabel.Text = ...
                sprintf('Measured SNR: %.1f dB', measuredSNR);

            % Decode only noisy samples; never pass the pressed key.
            result = app.decodeDTMF(app.ReceivedTone);
            app.DecodedLabel.Text = result.Key;

            if result.Valid
                app.DecodedLabel.FontColor = [0.02 0.48 0.35];

                app.StatusLabel.Text = sprintf( ...
                    'Decoded %s | Peaks %.1f + %.1f Hz | Peak/floor %.1f / %.1f dB', ...
                    result.Key, result.PeaksHz(1), result.PeaksHz(2), ...
                    result.MarginDB(1), result.MarginDB(2));
            else
                app.DecodedLabel.FontColor = [0.80 0.28 0.08];
                app.StatusLabel.Text = ['Uncertain: ' result.Reason];
            end
            app.StatusLabel.Tooltip = app.StatusLabel.Text;

            % Update existing graphics objects for smooth interaction.
            set(app.CleanLine, ...
                'XData', 1000*app.Time, 'YData', app.CleanTone);

            set(app.ReceivedLine, ...
                'XData', 1000*app.Time, 'YData', app.ReceivedTone);

            timeLimit = max(2.2, 1.1*max(abs(app.ReceivedTone)));
            ylim(app.TimeAxes, [-timeLimit timeLimit]);
            title(app.TimeAxes, ...
                sprintf('Time domain | Target SNR %.1f dB', snrDB));

            set(app.SpectrumLine, ...
                'XData', result.Frequency, 'YData', result.Magnitude);

            set(app.PeakMarkers, ...
                'XData', result.PeaksHz, ...
                'YData', result.PeakAmplitude);

            f = result.PeaksHz;
            a = result.PeakAmplitude;
            set(app.PeakStems, ...
                'XData', [f(1) f(1) NaN f(2) f(2)], ...
                'YData', [0 a(1) NaN 0 a(2)]);

            yTop = max(0.1, ...
                1.35*max(result.Magnitude(result.Frequency <= 2000)));
            ylim(app.SpectrumAxes, [0 yTop]);

            set(app.LowPeakText, ...
                'Position', [f(1) a(1)+0.04*yTop 0], ...
                'String', sprintf('L %.1f Hz', f(1)));

            set(app.HighPeakText, ...
                'Position', [f(2) a(2)+0.04*yTop 0], ...
                'String', sprintf('H %.1f Hz', f(2)));

            title(app.SpectrumAxes, ...
                'Single-sided FFT | Hann window | Red: detected peaks');

            drawnow limitrate nocallbacks
        end

        function result = decodeDTMF(app, samples, sampleRate)
            % Safe rejection defaults for silence or malformed input.
            % Default settings preserve the generator's original analysis.
            if nargin < 3
                sampleRate = app.Fs;
                fftLength = app.NFFT;
            else
                % Analyze uploaded audio at its native rate, without resampling
                % or a Signal Processing Toolbox dependency.
                fftLength = 2^nextpow2(sampleRate*app.NFFT/app.Fs);
            end
            f = (0:fftLength/2)' * sampleRate/fftLength;

            result = struct('Key', '?', 'Valid', false, ...
                'PeaksHz', [NaN NaN], 'PeakAmplitude', [NaN NaN], ...
                'MarginDB', [NaN NaN], 'Frequency', f, ...
                'Magnitude', zeros(size(f)), ...
                'Reason', 'No usable signal');

            if ~isnumeric(samples) || ~isvector(samples) || ...
                    ~isreal(samples) || ...
                    numel(samples) ~= round(sampleRate*app.ToneDuration) || ...
                    any(~isfinite(samples(:)))
                return
            end

            x = double(samples(:));
            x = x - mean(x); % Remove DC before spectral analysis.

            if max(abs(x)) < 1e-10
                result.Reason = 'Silence';
                return
            end

            % 3. FFT: construct a Hann window to suppress leakage.
            % At 8 kHz, zero-pad 800 observed samples to 2048 FFT points.
            % Fs/NFFT = 3.90625 Hz is BIN SPACING. Zero padding does
            % not improve the resolving power of the 100 ms frame.
            L = numel(x);
            window = 0.5 - 0.5*cos(2*pi*(0:L-1)'/(L-1));
            Y = fft(x .* window, fftLength);

            % Correct amplitude normalization uses the window sum,
            % rather than the zero-padded FFT length.
            magnitude = abs(Y(1:fftLength/2+1)) / sum(window);

            % Single-sided spectrum: double positive-frequency bins,
            % except DC and the Nyquist bin.
            magnitude(2:end-1) = 2*magnitude(2:end-1);
            result.Magnitude = magnitude;

            % 4. Peak picking within the specified frequency bands.
            % Maximizing magnitude also maximizes squared magnitude.
            lowBins = find(f >= 600 & f <= 1000);
            highBins = find(f >= 1200 & f <= 1700);

            [pLow, iLow] = max(magnitude(lowBins));
            [pHigh, iHigh] = max(magnitude(highBins));

            detectedLow = f(lowBins(iLow));
            detectedHigh = f(highBins(iHigh));

            result.PeaksHz = [detectedLow detectedHigh];
            result.PeakAmplitude = [pLow pHigh];

            % 5. Match peaks to the nearest nominal row and column.
            [errorLow, r] = ...
                min(abs(app.LowFrequencies - detectedLow));
            [errorHigh, c] = ...
                min(abs(app.HighFrequencies - detectedHigh));

            % 6. Estimate background outside each peak's main lobe.
            lowBackground = magnitude( ...
                lowBins(abs(f(lowBins)-detectedLow) > 30));
            highBackground = magnitude( ...
                highBins(abs(f(highBins)-detectedHigh) > 30));

            floorLow = max(median(lowBackground), eps);
            floorHigh = max(median(highBackground), eps);

            result.MarginDB = ...
                20*log10([pLow/floorLow pHigh/floorHigh]);

            balanceDB = ...
                20*log10(max(pHigh,eps)/max(pLow,eps));

            % Conservative demonstration checks:
            %   - Frequency error <= 1.5% of nominal.
            %   - Both peaks >= 14 dB above their background.
            %   - Relative tone amplitude imbalance <= 6 dB.
            %
            % These are not a complete telecom compliance validator.
            % Even at 0 dB input SNR, a full 800-sample frame usually
            % produces clear spectral peaks. Reject uncertain frames
            % with '?' instead of forcing an arbitrary key.
            if errorLow > 0.015*app.LowFrequencies(r) || ...
                    errorHigh > 0.015*app.HighFrequencies(c)

                result.Reason = 'Peak outside DTMF tolerance';

            elseif any(result.MarginDB < 14)
                result.Reason = 'Peaks too weak above noise';

            elseif abs(balanceDB) > 6
                result.Reason = 'Unbalanced or missing tone';

            else
                result.Key = app.KeyMap(r,c);
                result.Valid = true;
                result.Reason = 'Accepted';
            end
        end

        function uploadAudioFile(app)
            [name, folder] = uigetfile( ...
                {'*.wav;*.mp3;*.flac;*.m4a;*.ogg;*.aif;*.aiff;*.au', ...
                 'Audio files'; '*.*', 'All files'}, 'Select DTMF audio file');
            if isequal(name, 0)
                return % Cancel keeps the previous result.
            end
            app.UploadAudioButton.Enable = 'off';
            app.AudioFileLabel.Text = name;
            app.AudioFileLabel.Tooltip = fullfile(folder, name);
            app.FileResultField.Value = '';
            app.FileStatusLabel.Text = 'Reading and analyzing audio...';
            app.FileStatusLabel.Tooltip = '';
            drawnow nocallbacks
            try
                [samples, sampleRate] = audioread(fullfile(folder, name));
                if isempty(samples) || any(~isfinite(samples(:)))
                    error('DTMF_App:InvalidAudio', 'The file contains no usable audio samples.');
                end
                if sampleRate < 4000
                    error('DTMF_App:LowSampleRate', ...
                        'The audio sample rate must be at least 4000 Hz.');
                end
                sequence = app.decodeAudioFile(samples, sampleRate);
                if isempty(sequence)
                    message = 'No key detected';
                else
                    message = ['Detected key(s): ' sequence];
                end
                app.FileResultField.Value = message;
                app.FileStatusLabel.Text = sprintf( ...
                    'Analysis complete | %.2f seconds | %d Hz | %d key(s) detected', ...
                    size(samples,1)/sampleRate, sampleRate, numel(sequence));
                fprintf('%s\n', message);
            catch exception
                app.FileResultField.Value = 'Unable to analyze audio file';
                app.FileStatusLabel.Text = 'Could not read or analyze this file. See the status tooltip for details.';
                app.FileStatusLabel.Tooltip = exception.message;
            end
            app.UploadAudioButton.Enable = 'on';
        end

        function sequence = decodeAudioFile(app, samples, sampleRate)
            % Overlapping windows find tones anywhere in the recording.
            % Pad both boundaries so a short clip or final tone is not skipped.
            frameLength = round(sampleRate*app.ToneDuration);
            hop = max(1, round(0.025*sampleRate));
            padding = zeros(floor(frameLength/2), size(samples,2));
            samples = [padding; samples; padding];
            sequence = '';
            lastKey = '';
            quietFrames = 0;
            for first = 1:hop:size(samples,1)-frameLength+1
                frame = samples(first:first+frameLength-1,:);
                frame = bsxfun(@minus, frame, mean(frame,1));
                % Select the strongest channel per frame rather than averaging:
                % opposite-phase stereo tones must not cancel each other out.
                [power, channel] = max(mean(frame.^2,1));
                result = app.decodeDTMF(frame(:,channel), sampleRate);
                spectralPower = result.Magnitude.^2;
                nearPair = abs(result.Frequency-result.PeaksHz(1)) <= 30 | ...
                    abs(result.Frequency-result.PeaksHz(2)) <= 30;
                concentration = sum(spectralPower(nearPair))/ ...
                    max(sum(spectralPower), eps);
                valid = result.Valid && power >= 1e-8 && concentration >= 0.65;
                if valid
                    quietFrames = 0;
                    if ~strcmp(lastKey, result.Key)
                        sequence = [sequence result.Key]; %#ok<AGROW>
                        lastKey = result.Key;
                    end
                else
                    quietFrames = quietFrames+1;
                    if quietFrames >= 3
                        lastKey = ''; % A pause allows a repeated key.
                    end
                end
                if mod(first-1, 40*hop) == 0
                    drawnow limitrate nocallbacks
                end
            end
        end

        function recordMicrophone(app)
            if ~isempty(app.MicRecorder)
                return % Ignore another click while recording or processing.
            end
            duration = app.MicDurationDropDown.Value;
            app.MicDurationDropDown.Enable = 'off';
            app.MicRecordButton.Enable = 'off';
            app.MicRecordButton.Text = 'Recording...';
            app.MicResultField.Value = '';
            app.MicStatusLabel.Text = sprintf( ...
                'Recording for %d seconds. Play your tone now...', duration);
            app.MicStatusLabel.Tooltip = '';
            drawnow nocallbacks
            try
                % Complete capture here instead of relying on a queued StopFcn
                % to advance the UI. Silence never extends the recording time.
                recorder = audiorecorder(44100, 16, 1);
                app.MicRecorder = recorder;
                recordblocking(recorder, duration);
                stop(recorder); % Explicitly stop before reading or decoding.
                if ~isvalid(app)
                    return
                end
                app.microphoneRecorded(recorder, duration);
            catch exception
                if isvalid(app)
                    app.microphoneError(exception);
                end
            end
        end

        function microphoneRecorded(app, recorder, duration)
            if isempty(app.MicRecorder) || ~isequal(recorder, app.MicRecorder)
                return
            end
            app.MicRecordButton.Text = 'Processing...';
            app.MicStatusLabel.Text = 'Recording stopped. Analyzing audio...';
            drawnow nocallbacks
            try
                sequence = '';
                if recorder.TotalSamples > 0
                    samples = getaudiodata(recorder, 'double');
                    % Only the selected recording duration is analyzed.
                    samples = samples(1:min(size(samples,1), ...
                        round(duration*recorder.SampleRate)), :);
                    sequence = app.decodeAudioFile(samples, recorder.SampleRate);
                end
                if isempty(sequence)
                    message = 'No key detected';
                else
                    message = ['Detected key(s): ' sequence];
                end
                app.MicResultField.Value = message;
                fprintf('Microphone: %s\n', message);
                app.releaseMicrophone();
                app.MicRecordButton.Text = 'Record';
                app.MicRecordButton.Enable = 'on';
                app.MicDurationDropDown.Enable = 'on';
                app.MicStatusLabel.Text = 'Ready. Click Record to record another key.';
            catch exception
                app.microphoneError(exception);
            end
        end

        function microphoneError(app, exception)
            app.releaseMicrophone();
            app.MicRecordButton.Text = 'Record';
            app.MicRecordButton.Enable = 'on';
            app.MicDurationDropDown.Enable = 'on';
            app.MicResultField.Value = 'Unable to record or analyze microphone audio';
            app.MicStatusLabel.Text = 'Check microphone permissions/default input, then click Record to retry.';
            app.MicStatusLabel.Tooltip = exception.message;
        end

        function releaseMicrophone(app)
            if ~isempty(app.MicRecorder)
                recorder = app.MicRecorder;
                app.MicRecorder = [];
                % Stop on normal completion, errors, and app closure.
                recorder.StopFcn = [];
                try
                    stop(recorder);
                catch
                    % A disconnected device must not prevent app cleanup.
                end
            end
        end

        function playTone(app)
            if isempty(app.ReceivedTone) || ~app.AudioCheckBox.Value
                return
            end

            % Play the received signal so channel noise is audible.
            % A 5 ms audio-only fade reduces boundary clicks.
            % The decoder still analyzes the complete original frame.
            audio = app.ReceivedTone;
            K = min(round(0.005*app.Fs), floor(numel(audio)/2));
            ramp = linspace(0,1,K)';

            audio(1:K) = audio(1:K).*ramp;
            audio(end-K+1:end) = ...
                audio(end-K+1:end).*flipud(ramp);

            try
                % Base MATLAB playback with automatic amplitude scaling.
                soundsc(audio, app.Fs, 16);
                app.AudioStatusLabel.Text = 'Audio enabled';
                app.AudioStatusLabel.Tooltip = '';

            catch exception
                % Preserve decoding and plotting without an audio device.
                app.AudioCheckBox.Value = false;
                app.AudioStatusLabel.Text = 'Audio unavailable';
                app.AudioStatusLabel.Tooltip = exception.message;
            end
        end

        function audioChanged(app)
            if app.AudioCheckBox.Value
                app.AudioStatusLabel.Text = 'Audio enabled';
            else
                app.AudioStatusLabel.Text = 'Audio muted';
            end
            app.AudioStatusLabel.Tooltip = '';
        end

        function clearHistory(app)
            app.DecodedSequence = '';
            app.History = cell(0,7);
            app.SequenceField.Value = '';
            app.LogTable.Data = app.History;

            app.StatusLabel.Text = ...
                'History cleared. Press a key to start a new sequence.';
            app.StatusLabel.Tooltip = app.StatusLabel.Text;
        end
    end

    methods (Access = public)
        function app = DTMF_App
            try
                app.createComponents();
                registerApp(app, app.UIFigure);
                app.UIFigure.Visible = 'on';

            catch exception
                delete(app);
                rethrow(exception);
            end

            if nargout == 0
                clear app
            end
        end

        function delete(app)
            app.releaseMicrophone();
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end
end
