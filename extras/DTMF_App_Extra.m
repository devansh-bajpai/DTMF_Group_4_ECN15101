classdef DTMF_App_finalized < matlab.apps.AppBase
    properties (Access = public)
        UIFigure
    end

    properties (Constant, Access = private)
        Fs = 8000
        ToneDuration = 0.1
        NFFT = 2048
        LowFrequencies = [697 770 852 941]
        HighFrequencies = [1209 1336 1477 1633]
        KeyMap = ['1' '2' '3' 'A'; '4' '5' '6' 'B'; ...
                  '7' '8' '9' 'C'; '*' '0' '#' 'D']
        MinPurity = 0.12
        MinDominanceDB = 6
        MaxTwistDB = 8
        FrequencyTolerance = 0.015
    end

    properties (Access = private)
        UI = struct()
        Graphics = struct()
        Time = []
        CurrentKey = ''
        CurrentRow = 1
        CurrentColumn = 1
        RandomFrame = struct()
        ReceivedTone = []
        ActiveButton = []
        MediumDemoKey = ''
        LastMediumKey = repmat(' ',4,4)
        Sequence = ''
        History = cell(0,10)
        Trace = []
        TraceOffset = 0
        TraceHasCurrent = false
        Busy = false
        StopRequested = false
        CloseAfterBenchmark = false
    end

    methods (Access = private)
        function createComponents(app)
            bg = [0.94 0.96 0.98]; ink = [0.12 0.18 0.28];
            screen = get(groot,'ScreenSize');
            w = min(1400,screen(3)-50); h = min(950,screen(4)-90);
            app.UIFigure = uifigure('Visible','off', ...
                'Name','DTMF | Generator, Decoder & DSP Lab', ...
                'Color',bg,'Position',[screen(1)+(screen(3)-w)/2 ...
                screen(2)+(screen(4)-h)/2 w h]);
            app.UIFigure.CloseRequestFcn = @(~,~) app.closeRequested();
            root = uigridlayout(app.UIFigure,[4 1]);
            root.Padding = [14 14 14 14]; root.RowSpacing = 10;
            root.RowHeight = {56,'1x',142,44}; root.Scrollable = 'on';
            root.BackgroundColor = bg; app.UI.Root = root;
            header = uigridlayout(root,[2 1]);
            header.Layout.Row = 1; header.Padding = [0 0 0 0];
            header.RowHeight = {32,20}; header.RowSpacing = 0;
            header.BackgroundColor = bg;
            uilabel(header,'Text','DTMF Signal Lab','FontSize',25, ...
                'FontWeight','bold','FontColor',ink);
            uilabel(header,'Text', ...
                '8 kHz sampling  |  100 ms tones  |  2048-point FFT  |  FFT + Goertzel', ...
                'FontColor',[0.4 0.46 0.55]);
            body = uigridlayout(root,[1 2]);
            body.Layout.Row = 2; body.ColumnWidth = {350,'1x'};
            body.Padding = [0 0 0 0]; body.ColumnSpacing = 12;
            body.BackgroundColor = bg;

            left = uigridlayout(body,[3 2]);
            left.Layout.Column = 1; left.RowHeight = {18,44,'1x'};
            left.ColumnWidth = {'1x','1x'}; left.Padding = [10 10 10 10];
            left.BackgroundColor = [1 1 1];
            app.label(left,'PRESSED',1,1);
            app.UI.OutputCaption = app.label(left,'DEMO OUTPUT',1,2);
            app.UI.Pressed = app.label(left,'-',2,1);
            app.UI.Output = app.label(left,'-',2,2);
            app.UI.Pressed.FontSize = 36; app.UI.Pressed.FontWeight = 'bold';
            app.UI.Output.FontSize = 36; app.UI.Output.FontWeight = 'bold';
            controls = uitabgroup(left);
            controls.Layout.Row = 3; controls.Layout.Column = [1 2];
            keypadTab = uitab(controls,'Title','Keypad');
            channelTab = uitab(controls,'Title','Channel');
            app.createKeypadTab(keypadTab);
            app.createChannelTab(channelTab);

            tabs = uitabgroup(body); tabs.Layout.Column = 2;
            signalTab = uitab(tabs,'Title','Signal analysis');
            specTab = uitab(tabs,'Title','Spectrogram');
            benchTab = uitab(tabs,'Title','Benchmark');
            app.createSignalTab(signalTab);
            app.createSpectrogramTab(specTab);
            app.createBenchmarkTab(benchTab);

            historyGrid = uigridlayout(root,[2 3]);
            historyGrid.Layout.Row = 3;
            historyGrid.RowHeight = {26,'1x'};
            historyGrid.ColumnWidth = {120,'1x',110};
            historyGrid.Padding = [0 0 0 0]; historyGrid.BackgroundColor = bg;
            app.label(historyGrid,'OUTPUT SEQUENCE',1,1);
            app.UI.Sequence = uieditfield(historyGrid,'text','Editable','off');
            app.UI.Sequence.Layout.Row = 1; app.UI.Sequence.Layout.Column = 2;
            b = uibutton(historyGrid,'Text','Clear history', ...
                'ButtonPushedFcn',@(~,~) app.clearHistory());
            b.Layout.Row = 1; b.Layout.Column = 3;
            app.UI.Log = uitable(historyGrid,'Data',app.History, ...
                'ColumnName',{'Time','Sent','Shown','Mode','FFT','Goertzel', ...
                'SNR dB','Window','Low Hz','High Hz'},'RowName',{});
            app.UI.Log.Layout.Row = 2; app.UI.Log.Layout.Column = [1 3];
            footer = uigridlayout(root,[2 1]); footer.Layout.Row = 4;
            footer.Padding = [0 0 0 0]; footer.RowHeight = {22,18};
            footer.RowSpacing = 0; footer.BackgroundColor = bg;
            app.UI.Status = uilabel(footer,'Text','Press a key to begin.');
            app.UI.AudioStatus = uilabel(footer,'Text', ...
                'Audio plays the received signal, including enabled channel effects.', ...
                'FontSize',11,'FontColor',[0.4 0.46 0.55]);
            app.UIFigure.SizeChangedFcn = @(~,~) app.resizeLayout();
            app.resizeLayout();
        end

        function createKeypadTab(app,parent)
            g = uigridlayout(parent,[9 2]);
            g.RowHeight = {'1x',22,48,22,28,28,24,24,30};
            g.ColumnWidth = {110,'1x'}; g.Padding = [8 8 8 8];
            g.RowSpacing = 5;
            pad = uigridlayout(g,[4 4]);
            pad.Layout.Row = 1; pad.Layout.Column = [1 2];
            pad.Padding = [0 0 0 0]; pad.RowSpacing = 6; pad.ColumnSpacing = 6;
            for r = 1:4
                for c = 1:4
                    color = [0.12 0.18 0.28];
                    if c == 4, color = [0.19 0.32 0.49]; end
                    b = uibutton(pad,'Text',app.KeyMap(r,c), ...
                        'FontSize',22,'FontWeight','bold','FontColor',[1 1 1], ...
                        'BackgroundColor',color,'Interruptible','off');
                    b.Layout.Row = r; b.Layout.Column = c;
                    b.UserData = struct('Row',r,'Column',c,'Color',color);
                    b.ButtonPushedFcn = @(src,~) app.padButtonPushed(src);
                end
            end
            app.UI.SNRLabel = app.label(g,'Requested AWGN SNR: 20.0 dB',2,[1 2]);
            app.UI.SNR = uislider(g,'Limits',[0 30],'Value',20, ...
                'MajorTicks',0:5:30);
            app.UI.SNR.Layout.Row = 3; app.UI.SNR.Layout.Column = [1 2];
            app.UI.SNR.ValueChangingFcn = @(~,ev) app.settingsChanged(ev.Value);
            app.UI.SNR.ValueChangedFcn = @(src,~) app.settingsChanged(src.Value);
            app.UI.Measured = app.label(g,'Measured AWGN SNR: -',4,[1 2]);
            app.label(g,'Window',5,1);
            app.UI.Window = uidropdown(g, ...
                'Items',{'Rectangular','Hann','Hamming'},'Value','Hann', ...
                'ValueChangedFcn',@(~,~) app.settingsChanged());
            app.UI.Window.Layout.Row = 5; app.UI.Window.Layout.Column = 2;
            app.label(g,'Output decoder',6,1);
            app.UI.Algorithm = uidropdown(g,'Items',{'FFT','Goertzel'}, ...
                'ValueChangedFcn',@(~,~) app.settingsChanged());
            app.UI.Algorithm.Layout.Row = 6; app.UI.Algorithm.Layout.Column = 2;
            app.UI.Demo = uicheckbox(g,'Text','SNR demo (artificial outputs)', ...
                'Value',true,'ValueChangedFcn',@(~,~) app.settingsChanged());
            app.UI.Demo.Layout.Row = 7; app.UI.Demo.Layout.Column = [1 2];
            app.UI.Demo.Tooltip = ...
                '<5 dB: ?; 5 to <15 dB: random wrong key; >=15 dB: sent key.';
            app.UI.Audio = uicheckbox(g,'Text','Play received tone','Value',true);
            app.UI.Audio.Layout.Row = 8; app.UI.Audio.Layout.Column = [1 2];
            b = uibutton(g,'Text','Replay audio', ...
                'ButtonPushedFcn',@(~,~) app.playTone());
            b.Layout.Row = 9; b.Layout.Column = [1 2];
        end

        function createChannelTab(app,parent)
            g = uigridlayout(parent,[11 2]);
            g.ColumnWidth = {'1x',100};
            g.RowHeight = {28,28,28,28,28,28,28,28,28,32,'1x'};
            g.Padding = [8 8 8 8]; g.RowSpacing = 7;
            app.UI.Hum = app.check(g,'Electrical hum',1);
            app.UI.HumHz = uidropdown(g,'Items',{'50 Hz','60 Hz'}, ...
                'Value','50 Hz','ValueChangedFcn',@(~,~) app.settingsChanged());
            app.UI.HumHz.Layout.Row = 1; app.UI.HumHz.Layout.Column = 2;
            app.UI.HumLevel = app.number(g,'Hum RMS (% of tone)',2,10,[0 200]);
            app.UI.Impulse = app.check(g,'Impulse noise',3);
            app.UI.Impulse.Layout.Column = [1 2];
            app.UI.ImpulseRate = app.number(g,'Impulse samples (%)',4,0.5,[0 10]);
            app.UI.ImpulseSize = app.number(g,'Impulse size (x RMS)',5,5,[0 20]);
            app.UI.Clipping = app.check(g,'Hard clipping',6);
            app.UI.ClipLevel = uieditfield(g,'numeric','Limits',[0.1 10], ...
                'Value',1.2,'ValueChangedFcn',@(~,~) app.settingsChanged());
            app.UI.ClipLevel.Layout.Row = 6; app.UI.ClipLevel.Layout.Column = 2;
            app.UI.ClipLevel.Tooltip = 'Absolute received-signal amplitude limit.';
            app.UI.Offset = app.number(g,'Frequency offset (%)',7,0,[-5 5]);
            app.UI.Twist = app.number(g,'High / low gain (dB)',8,0,[-12 12]);
            app.label(g,'Effects also apply to benchmark trials.',9,[1 2]);
            b = uibutton(g,'Text','Reset channel effects', ...
                'ButtonPushedFcn',@(~,~) app.resetChannel());
            b.Layout.Row = 10; b.Layout.Column = [1 2];
            note = uitextarea(g,'Editable','off','Value',{ ...
                'Order: tone gain + frequency offset; hum + impulses + AWGN; clipping.', ...
                'AWGN power is referenced to the clean, gain-adjusted tone.', ...
                'Slider changes reuse this keypress''s noise realization.', ...
                'The benchmark tests real decoding, even with SNR demo enabled.'});
            note.Layout.Row = 11; note.Layout.Column = [1 2];
        end

        function createSignalTab(app,parent)
            g = uigridlayout(parent,[4 1]);
            g.RowHeight = {24,'1x','1x',94}; g.Padding = [8 8 8 8];
            g.BackgroundColor = [0.055 0.085 0.14];
            app.UI.DB = uicheckbox(g,'Text', ...
                'Log spectrum (dB) - useful for comparing window leakage', ...
                'FontColor',[0.88 0.93 0.98], ...
                'ValueChangedFcn',@(~,~) app.settingsChanged());
            app.UI.DB.Layout.Row = 1;
            app.UI.TimeAxes = app.darkAxes(g,2,'Time waveform','Time (ms)','Amplitude');
            ax = app.UI.TimeAxes;
            app.Graphics.Clean = plot(ax,nan,nan,'Color',[0.5 0.6 0.7], ...
                'LineWidth',1,'DisplayName','Transmitted'); hold(ax,'on');
            app.Graphics.Received = plot(ax,nan,nan,'Color',[0.22 0.68 1], ...
                'DisplayName','Received'); hold(ax,'off');
            xlim(ax,[0 100]); legend(ax,'Location','northeast', ...
                'TextColor',[0.9 0.94 1],'Color',g.BackgroundColor);
            app.UI.SpectrumAxes = app.darkAxes(g,3,'Spectrum', ...
                'Frequency (Hz)','Single-sided magnitude');
            ax = app.UI.SpectrumAxes;
            app.Graphics.Spectrum = plot(ax,nan,nan,'Color',[0.22 0.68 1], ...
                'DisplayName','FFT'); hold(ax,'on');
            app.Graphics.Goertzel = plot(ax,nan,nan,'o','Color',[0.3 0.9 0.6], ...
                'MarkerSize',5,'DisplayName','Goertzel: nominal frequencies');
            app.Graphics.Peaks = plot(ax,nan,nan,'rv','MarkerFaceColor','r', ...
                'MarkerSize',7,'DisplayName','FFT band peaks');
            app.Graphics.LowText = text(ax,0,0,'','Color',[1 0.45 0.45], ...
                'VerticalAlignment','bottom','HorizontalAlignment','center','FontSize',10);
            app.Graphics.HighText = text(ax,0,0,'','Color',[1 0.45 0.45], ...
                'VerticalAlignment','bottom','HorizontalAlignment','center','FontSize',10);
            hold(ax,'off'); xlim(ax,[0 2000]);
            legend(ax,'Location','northeast','TextColor',[0.9 0.94 1], ...
                'Color',g.BackgroundColor,'FontSize',9);
            app.UI.Live = uitable(g,'ColumnName',{'Actual decoder','Key','State', ...
                'Pair power est. %','Min margin dB','Time us'},'RowName',{});
            app.UI.Live.Layout.Row = 4;
            app.UI.Live.ColumnWidth = {100,40,225,112,110,95};
            app.UI.Live.Tooltip = ['Pair power is a heuristic estimate, not a probability; ' ...
                'it can exceed 100%. Live timings are single-frame measurements.'];
        end

        function createSpectrogramTab(app,parent)
            g = uigridlayout(parent,[2 1]);
            g.RowHeight = {42,'1x'}; g.Padding = [8 8 8 8];
            g.BackgroundColor = [0.055 0.085 0.14];
            note = app.label(g,sprintf(['Rolling 8 s key sequence: 100 ms tones + 30 ms gaps.\n' ...
                '512-sample window, 128-sample hop; current window selection applies.']),1,1);
            note.FontColor = [0.88 0.93 0.98];
            app.UI.SpectrogramAxes = app.darkAxes(g,2,'Sequence spectrogram', ...
                'Sequence time (s)','Frequency (Hz)');
            ax = app.UI.SpectrogramAxes;
            app.Graphics.Spectrogram = imagesc(ax,[0 0.1],[0 2000],-100*ones(2));
            hold(ax,'off');
            ax.YDir = 'normal'; xlim(ax,[0 0.1]); ylim(ax,[0 2000]);
            caxis(ax,[-80 0]); colormap(ax,parula(256));
            cb = colorbar(ax); cb.Color = [0.88 0.93 0.98];
            cb.Label.String = 'Power spectral density (dB / Hz)';
            cb.Label.Color = cb.Color;
        end

        function createBenchmarkTab(app,parent)
            g = uigridlayout(parent,[3 1]);
            g.RowHeight = {64,58,'1x'}; g.Padding = [8 8 8 8];
            top = uigridlayout(g,[2 5]); top.Layout.Row = 1;
            top.RowHeight = {20,30}; top.ColumnWidth = {'1x','1x','1x','1x',130};
            top.Padding = [0 0 0 0]; top.RowSpacing = 2;
            labels = {'Start SNR (dB)','End SNR (dB)','Step (dB)','Trials / key / SNR'};
            for k = 1:4, app.label(top,labels{k},1,k); end
            app.UI.StartSNR = uieditfield(top,'numeric','Value',-20,'Limits',[-40 40]);
            app.UI.EndSNR = uieditfield(top,'numeric','Value',30,'Limits',[-40 40]);
            app.UI.StepSNR = uieditfield(top,'numeric','Value',5,'Limits',[1 40]);
            app.UI.Trials = uieditfield(top,'numeric','Value',20,'Limits',[1 200]);
            fields = {app.UI.StartSNR,app.UI.EndSNR,app.UI.StepSNR,app.UI.Trials};
            for k = 1:4
                fields{k}.Layout.Row = 2; fields{k}.Layout.Column = k;
            end
            app.UI.Run = uibutton(top,'Text','Run benchmark', ...
                'ButtonPushedFcn',@(~,~) app.runBenchmark());
            app.UI.Run.Layout.Row = [1 2]; app.UI.Run.Layout.Column = 5;
            app.UI.BenchmarkNote = uitextarea(g,'Editable','off','Value',{ ...
                'Real decisions only. Each decoder receives exactly the same noisy frame.', ...
                'Default: 320 frames/SNR; fixed seed 12345; captures current window + channel.'});
            app.UI.BenchmarkNote.Layout.Row = 2;
            tabs = uitabgroup(g); tabs.Layout.Row = 3;
            rateTab = uitab(tabs,'Title','Accuracy vs SNR');
            timingTab = uitab(tabs,'Title','Processing time');
            resultTab = uitab(tabs,'Title','Results');
            rg = uigridlayout(rateTab,[1 1]);
            app.UI.RateAxes = uiaxes(rg); ax = app.UI.RateAxes;
            title(ax,'Actual correct / incorrect / rejected decisions');
            xlabel(ax,'Requested AWGN SNR (dB)'); ylabel(ax,'Frames (%)');
            grid(ax,'on'); ylim(ax,[0 100]);
            tg = uigridlayout(timingTab,[1 1]);
            app.UI.TimingAxes = uiaxes(tg); ax = app.UI.TimingAxes;
            title(ax,'Median decoding time per frame');
            xlabel(ax,'Requested AWGN SNR (dB)'); ylabel(ax,'Time (microseconds)');
            grid(ax,'on');
            tabg = uigridlayout(resultTab,[1 1]);
            app.UI.Results = uitable(tabg,'RowName',{},'ColumnName',{ ...
                'SNR dB','Frames','FFT correct %','FFT wrong %','FFT reject %', ...
                'Goertzel correct %','Goertzel wrong %','Goertzel reject %', ...
                'FFT us','Goertzel us'});
        end

        function h = label(~,g,txt,row,col)
            h = uilabel(g,'Text',txt,'FontSize',11);
            h.Layout.Row = row; h.Layout.Column = col;
        end

        function h = check(app,g,txt,row)
            h = uicheckbox(g,'Text',txt, ...
                'ValueChangedFcn',@(~,~) app.settingsChanged());
            h.Layout.Row = row; h.Layout.Column = 1;
        end

        function h = number(app,g,txt,row,value,limits)
            app.label(g,txt,row,1);
            h = uieditfield(g,'numeric','Value',value,'Limits',limits, ...
                'ValueChangedFcn',@(~,~) app.settingsChanged());
            h.Layout.Row = row; h.Layout.Column = 2;
        end

        function ax = darkAxes(~,g,row,heading,xtext,ytext)
            ax = uiaxes(g); ax.Layout.Row = row;
            ax.Color = [0.055 0.085 0.14];
            ax.XColor = [0.88 0.93 0.98]; ax.YColor = ax.XColor;
            ax.GridColor = [0.45 0.55 0.7]; ax.GridAlpha = 0.22;
            title(ax,heading,'Color',ax.XColor,'FontSize',12);
            xlabel(ax,xtext); ylabel(ax,ytext); grid(ax,'on');
            ax.XLabel.Color = ax.XColor; ax.YLabel.Color = ax.YColor;
            ax.Toolbar.Visible = 'off';
            hold(ax,'on'); % Preserve axes styling when creating plot objects.
        end

        function resizeLayout(app)
            p = app.UIFigure.Position;
            app.UI.Root.ColumnWidth = {max(1060,p(3)-28)};
            app.UI.Root.RowHeight = {56,max(610,p(4)-300),142,44};
        end

        function cfg = settings(app)
            cfg.Window = app.UI.Window.Value;
            cfg.Hum = app.UI.Hum.Value;
            cfg.HumHz = sscanf(app.UI.HumHz.Value,'%f',1);
            cfg.HumLevel = app.UI.HumLevel.Value/100;
            cfg.Impulse = app.UI.Impulse.Value;
            cfg.ImpulseRate = app.UI.ImpulseRate.Value/100;
            cfg.ImpulseSize = app.UI.ImpulseSize.Value;
            cfg.Clipping = app.UI.Clipping.Value;
            cfg.ClipLevel = app.UI.ClipLevel.Value;
            cfg.Offset = app.UI.Offset.Value/100;
            cfg.Twist = app.UI.Twist.Value;
        end

        function resetChannel(app)
            if app.Busy, return; end
            app.UI.Hum.Value = false; app.UI.HumHz.Value = '50 Hz';
            app.UI.HumLevel.Value = 10; app.UI.Impulse.Value = false;
            app.UI.ImpulseRate.Value = 0.5; app.UI.ImpulseSize.Value = 5;
            app.UI.Clipping.Value = false; app.UI.ClipLevel.Value = 1.2;
            app.UI.Offset.Value = 0; app.UI.Twist.Value = 0;
            app.settingsChanged();
        end

        function padButtonPushed(app,button)
            if app.Busy, return; end
            if ~isempty(app.ActiveButton) && isvalid(app.ActiveButton)
                app.ActiveButton.BackgroundColor = app.ActiveButton.UserData.Color;
            end
            button.BackgroundColor = [0.05 0.48 0.9]; app.ActiveButton = button;
            app.CurrentRow = button.UserData.Row;
            app.CurrentColumn = button.UserData.Column;
            app.CurrentKey = app.KeyMap(app.CurrentRow,app.CurrentColumn);
            app.MediumDemoKey = ''; % New click permits a new random demo output.
            app.RandomFrame = app.randomFrame([],false);
            app.UI.Pressed.Text = app.CurrentKey;
            [shown,fr,gr] = app.refreshAnalysis(app.UI.SNR.Value);
            app.appendTrace(); app.updateSpectrogram();
            app.Sequence = [app.Sequence shown];
            if numel(app.Sequence)>200, app.Sequence = app.Sequence(end-199:end); end
            app.UI.Sequence.Value = app.Sequence;
            mode = app.UI.Algorithm.Value;
            if app.UI.Demo.Value, mode = 'DEMO'; end
            row = {datestr(now,'HH:MM:SS'),app.CurrentKey,shown,mode, ...
                fr.Key,gr.Key,app.UI.SNR.Value,app.UI.Window.Value, ...
                fr.LowHz,fr.HighHz};
            app.History = [row;app.History];
            if size(app.History,1)>100, app.History = app.History(1:100,:); end
            app.UI.Log.Data = app.History;
            if app.UI.Audio.Value, app.playTone(); end
        end

        function settingsChanged(app,snrValue)
            if app.Busy, return; end
            if nargin<2, snrValue = app.UI.SNR.Value; end
            app.UI.SNRLabel.Text = sprintf('Requested AWGN SNR: %.1f dB',snrValue);
            if app.UI.Demo.Value
                app.UI.OutputCaption.Text = 'DEMO OUTPUT';
            else
                app.UI.OutputCaption.Text = [upper(app.UI.Algorithm.Value) ' OUTPUT'];
            end
            if ~isempty(app.CurrentKey)
                app.refreshAnalysis(snrValue);
                % Edit the last frame rather than adding duplicate keypresses.
                if app.TraceHasCurrent && numel(app.Trace)>=numel(app.ReceivedTone)
                    app.Trace(end-numel(app.ReceivedTone)+1:end) = app.ReceivedTone;
                end
            end
            app.updateSpectrogram();
        end

        function random = randomFrame(app,stream,randomPhase)
            L = numel(app.Time);
            if isempty(stream)
                random.AWGN = randn(L,1); random.Events = rand(L,1);
                random.Impulses = randn(L,1); random.HumPhase = 2*pi*rand;
                random.Phase = [0 0];
            else
                random.AWGN = randn(stream,L,1); random.Events = rand(stream,L,1);
                random.Impulses = randn(stream,L,1);
                random.HumPhase = 2*pi*rand(stream);
                random.Phase = [0 0];
                if randomPhase, random.Phase = 2*pi*rand(stream,1,2); end
            end
        end

        function [received,clean,measured] = channel(app,row,col,snrDB,cfg,random)
            % Synthesis: nominal sinusoids, optional common frequency offset,
            % and high-tone gain (twist). With zero effects this is sin + sin.
            fl = app.LowFrequencies(row)*(1+cfg.Offset);
            fh = app.HighFrequencies(col)*(1+cfg.Offset);
            clean = sin(2*pi*fl*app.Time+random.Phase(1)) + ...
                10^(cfg.Twist/20)*sin(2*pi*fh*app.Time+random.Phase(2));
            power = mean(clean.^2);
            % AWGN variance follows the requested signal-to-noise power ratio.
            noise = sqrt(power/10^(snrDB/10))*random.AWGN;
            received = clean+noise;
            if cfg.Hum
                received = received + sqrt(2*power)*cfg.HumLevel* ...
                    sin(2*pi*cfg.HumHz*app.Time+random.HumPhase);
            end
            if cfg.Impulse
                received = received + cfg.ImpulseSize*sqrt(power)* ...
                    random.Impulses.*(random.Events<cfg.ImpulseRate);
            end
            if cfg.Clipping
                received = max(-cfg.ClipLevel,min(cfg.ClipLevel,received));
            end
            % This readout measures AWGN alone, before clipping; not total SINR.
            measured = 10*log10(power/max(mean(noise.^2),realmin));
        end

        function w = windowVector(~,name,L)
            n = (0:L-1)';
            switch name
                case 'Hann', w = 0.5-0.5*cos(2*pi*n/(L-1));
                case 'Hamming', w = 0.54-0.46*cos(2*pi*n/(L-1));
                otherwise, w = ones(L,1);
            end
        end

        function ctx = decoderContext(app,name)
            ctx.Window = app.windowVector(name,numel(app.Time));
            ctx.WindowSum = sum(ctx.Window);
            ctx.Frequency = (0:app.NFFT/2)'*app.Fs/app.NFFT;
            ctx.LowBins = find(ctx.Frequency>=600 & ctx.Frequency<=1000);
            ctx.HighBins = find(ctx.Frequency>=1200 & ctx.Frequency<=1700);
            ctx.Nominal = [app.LowFrequencies app.HighFrequencies];
            ctx.NearBins = cell(1,8);
            for k = 1:8
                ctx.NearBins{k} = find(abs(ctx.Frequency-ctx.Nominal(k)) ...
                    <=app.FrequencyTolerance*ctx.Nominal(k));
            end
            omega = 2*pi*ctx.Nominal/app.Fs;
            ctx.Coefficient = 2*cos(omega);
            ctx.DelayPhase = exp(-1i*omega);
        end

        function [result,spectrum] = decodeDTMF(app,x,method,ctx)
            % No sent key or SNR is passed here: decisions use the signal only.
            result = struct('Key','?','Valid',false,'Reason','Silent/invalid frame', ...
                'LowHz',nan,'HighHz',nan,'Amplitudes',[0 0], ...
                'Responses',zeros(1,8),'Purity',0,'MarginDB',-inf,'TwistDB',nan);
            spectrum = zeros(app.NFFT/2+1,1);
            if numel(x)~=numel(ctx.Window) || any(~isfinite(x(:))), return; end
            x = x(:)-mean(x(:)); power = mean(x.^2);
            if power<1e-12, return; end
            z = x.*ctx.Window; % Windowing controls spectral leakage.
            if strcmp(method,'FFT')
                % Zero padding gives 3.90625 Hz bin spacing; it does not add
                % independent resolution beyond the 100 ms observation time.
                y = fft(z,app.NFFT);
                spectrum = abs(y(1:app.NFFT/2+1))/ctx.WindowSum;
                spectrum(2:end-1) = 2*spectrum(2:end-1);
                % Peak picking is performed separately in the two DTMF bands.
                [al,il] = max(spectrum(ctx.LowBins));
                [ah,ih] = max(spectrum(ctx.HighBins));
                fl = ctx.Frequency(ctx.LowBins(il));
                fh = ctx.Frequency(ctx.HighBins(ih));
                [~,row] = min(abs(app.LowFrequencies-fl));
                [~,col] = min(abs(app.HighFrequencies-fh));
                response = zeros(1,8);
                for k = 1:8, response(k) = max(spectrum(ctx.NearBins{k})); end
                frequencyOK = abs(fl-app.LowFrequencies(row)) <= ...
                    app.FrequencyTolerance*app.LowFrequencies(row) && ...
                    abs(fh-app.HighFrequencies(col)) <= ...
                    app.FrequencyTolerance*app.HighFrequencies(col);
            else
                % Goertzel recurrence: s[n]=z[n]+2*cos(w)*s[n-1]-s[n-2].
                % Base MATLAB filter evaluates it with zero initial state.
                % The final two states give DTFT magnitude at each nominal
                % frequency, even when that frequency is not an FFT bin.
                response = zeros(1,8);
                for k = 1:8
                    s = filter(1,[1 -ctx.Coefficient(k) 1],z);
                    response(k) = 2*abs(s(end)-ctx.DelayPhase(k)*s(end-1)) ...
                        /ctx.WindowSum;
                end
                [al,row] = max(response(1:4));
                [ah,col] = max(response(5:8));
                fl = app.LowFrequencies(row); fh = app.HighFrequencies(col);
                % These are probe frequencies, NOT frequency estimates.
                frequencyOK = true;
            end
            % Reject ambiguous/noise-dominated frames instead of always
            % forcing the nearest key. Both methods share these thresholds.
            othersLow = response(setdiff(1:4,row));
            othersHigh = response(4+setdiff(1:4,col));
            margin = min(20*log10([al ah]./max( ...
                [max(othersLow) max(othersHigh)],eps)));
            purity = (al^2+ah^2)/(2*power);
            twist = 20*log10(max(ah,eps)/max(al,eps));
            result.LowHz = fl; result.HighHz = fh;
            result.Amplitudes = [al ah]; result.Responses = response;
            result.Purity = purity; result.MarginDB = margin; result.TwistDB = twist;
            if ~frequencyOK
                result.Reason = 'FFT peak outside frequency tolerance';
            elseif purity<app.MinPurity
                result.Reason = 'Tone-pair power too weak';
            elseif margin<app.MinDominanceDB
                result.Reason = 'Competing tones / ambiguous band peaks';
            elseif abs(twist)>app.MaxTwistDB
                result.Reason = 'Low/high amplitude imbalance';
            else
                % Map the selected row and column to the standard 4x4 keypad.
                result.Key = app.KeyMap(row,col); result.Valid = true;
                result.Reason = 'Accepted';
            end
        end

        function [shown,fr,gr] = refreshAnalysis(app,snrValue)
            cfg = app.settings(); ctx = app.decoderContext(cfg.Window);
            [rx,clean,measured] = app.channel(app.CurrentRow,app.CurrentColumn, ...
                snrValue,cfg,app.RandomFrame);
            app.ReceivedTone = rx;
            timer = tic; [fr,spectrum] = app.decodeDTMF(rx,'FFT',ctx); ft = toc(timer);
            timer = tic; gr = app.decodeDTMF(rx,'Goertzel',ctx); gt = toc(timer);
            selected = fr;
            if strcmp(app.UI.Algorithm.Value,'Goertzel'), selected = gr; end
            shown = selected.Key;
            if app.UI.Demo.Value, shown = app.demoOutput(snrValue); end
            app.UI.Output.Text = shown;
            if shown=='?'
                app.UI.Output.FontColor = [0.75 0.45 0.05];
            elseif shown==app.CurrentKey
                app.UI.Output.FontColor = [0.02 0.48 0.35];
            else
                app.UI.Output.FontColor = [0.85 0.16 0.2];
            end
            app.UI.SNRLabel.Text = sprintf('Requested AWGN SNR: %.1f dB',snrValue);
            app.UI.Measured.Text = sprintf('Measured AWGN SNR: %.1f dB (pre-clip)',measured);
            set(app.Graphics.Clean,'XData',app.Time*1000,'YData',clean);
            set(app.Graphics.Received,'XData',app.Time*1000,'YData',rx);
            span = max(2.2,1.08*max(abs([clean;rx])));
            ylim(app.UI.TimeAxes,[-span span]);
            peaks = fr.Amplitudes; probes = gr.Responses;
            if app.UI.DB.Value
                spectrum = 20*log10(max(spectrum,1e-6));
                peaks = 20*log10(max(peaks,1e-6));
                probes = 20*log10(max(probes,1e-6));
                ylim(app.UI.SpectrumAxes,[-80 max(6,max(spectrum)+6)]);
                ylabel(app.UI.SpectrumAxes,'Magnitude (dB re 1)');
            else
                ylim(app.UI.SpectrumAxes,[0 max(0.1,1.3*max([spectrum;probes(:)]))]);
                ylabel(app.UI.SpectrumAxes,'Single-sided magnitude');
            end
            set(app.Graphics.Spectrum,'XData',ctx.Frequency,'YData',spectrum);
            set(app.Graphics.Goertzel,'XData',ctx.Nominal,'YData',probes);
            set(app.Graphics.Peaks,'XData',[fr.LowHz fr.HighHz],'YData',peaks);
            set(app.Graphics.LowText,'Position',[fr.LowHz peaks(1) 0], ...
                'String',sprintf(' %.1f Hz',fr.LowHz));
            set(app.Graphics.HighText,'Position',[fr.HighHz peaks(2) 0], ...
                'String',sprintf(' %.1f Hz',fr.HighHz));
            title(app.UI.SpectrumAxes,sprintf('%s window | FFT peaks + Goertzel probes',cfg.Window));
            app.UI.Live.Data = { ...
                'FFT',fr.Key,fr.Reason,round(100*fr.Purity,1),round(fr.MarginDB,1),round(ft*1e6,1); ...
                'Goertzel',gr.Key,gr.Reason,round(100*gr.Purity,1),round(gr.MarginDB,1),round(gt*1e6,1)};
            mode = ['Actual ' app.UI.Algorithm.Value];
            if app.UI.Demo.Value, mode = 'Artificial SNR demo'; end
            app.UI.Status.Text = sprintf('%s: %s  |  Actual FFT: %s  |  Actual Goertzel: %s', ...
                mode,shown,fr.Key,gr.Key);
            app.UI.Status.Tooltip = sprintf('FFT: %s\nGoertzel: %s',fr.Reason,gr.Reason);
        end

        function key = demoOutput(app,snrDB)
            % Deliberate presentation-only errors. Never used in benchmarks.
            if snrDB<5
                key = '?';
            elseif snrDB<15
                if isempty(app.MediumDemoKey)
                    previous = app.LastMediumKey(app.CurrentRow,app.CurrentColumn);
                    choices = reshape(app.KeyMap,1,[]);
                    choices(choices==app.CurrentKey | choices==previous) = [];
                    key = choices(randi(numel(choices)));
                    app.MediumDemoKey = key;
                    app.LastMediumKey(app.CurrentRow,app.CurrentColumn) = key;
                end
                key = app.MediumDemoKey;
            else
                key = app.CurrentKey;
            end
        end

        function appendTrace(app)
            if ~isempty(app.Trace)
                app.Trace = [app.Trace;zeros(round(0.03*app.Fs),1)];
            end
            app.Trace = [app.Trace;app.ReceivedTone];
            excess = max(0,numel(app.Trace)-8*app.Fs);
            if excess>0
                app.Trace(1:excess) = [];
                app.TraceOffset = app.TraceOffset+excess/app.Fs;
            end
            app.TraceHasCurrent = true;
        end

        function updateSpectrogram(app)
            if isempty(app.Trace), return; end
            % Manual short-time Fourier transform, avoiding toolbox functions.
            L = 512; hop = 128;
            w = app.windowVector(app.UI.Window.Value,L);
            padded = [zeros(L/2,1);app.Trace;zeros(L/2,1)];
            starts = 1:hop:numel(padded)-L+1;
            indices = (0:L-1)'+starts;
            frames = padded(indices).*w;
            Y = fft(frames,app.NFFT,1);
            psd = abs(Y(1:app.NFFT/2+1,:)).^2/(app.Fs*sum(w.^2));
            psd(2:end-1,:) = 2*psd(2:end-1,:);
            f = (0:app.NFFT/2)'*app.Fs/app.NFFT;
            keep = f<=2000;
            t = app.TraceOffset+(starts-1)/app.Fs;
            set(app.Graphics.Spectrogram,'XData',[t(1) t(end)], ...
                'YData',[0 f(find(keep,1,'last'))], ...
                'CData',10*log10(max(psd(keep,:),1e-12)));
            xlim(app.UI.SpectrogramAxes, ...
                [app.TraceOffset app.TraceOffset+numel(app.Trace)/app.Fs]);
            ylim(app.UI.SpectrogramAxes,[0 2000]);
        end

        function playTone(app)
            if app.Busy || isempty(app.ReceivedTone), return; end
            audio = app.ReceivedTone;
            % Fade only the playback copy to avoid endpoint clicks.
            n = min(round(0.005*app.Fs),floor(numel(audio)/2));
            fade = linspace(0,1,n)';
            audio(1:n) = audio(1:n).*fade;
            audio(end-n+1:end) = audio(end-n+1:end).*flipud(fade);
            try
                soundsc(audio,app.Fs,16);
                app.UI.AudioStatus.Text = 'Playing received tone (scaled for audio playback).';
            catch ME
                app.UI.Audio.Value = false;
                app.UI.AudioStatus.Text = 'Audio unavailable; signal analysis remains active.';
                app.UI.AudioStatus.Tooltip = ME.message;
            end
        end

        function clearHistory(app)
            if app.Busy, return; end
            app.Sequence = ''; app.History = cell(0,10);
            app.UI.Sequence.Value = ''; app.UI.Log.Data = app.History;
            app.Trace = []; app.TraceOffset = 0; app.TraceHasCurrent = false;
            set(app.Graphics.Spectrogram,'XData',[0 0.1],'YData',[0 2000], ...
                'CData',-100*ones(2));
            xlim(app.UI.SpectrogramAxes,[0 0.1]);
        end

        function textValue = configurationText(~,cfg)
            textValue = sprintf(['%s | Hum %d (%.0f Hz, %.1f%% RMS) | ' ...
                'Impulses %d (%.2f%%, %.1fx) | Clip %d (%.2f) | ' ...
                'Offset %+.2f%% | High/low %+.1f dB'], ...
                cfg.Window,cfg.Hum,cfg.HumHz,100*cfg.HumLevel, ...
                cfg.Impulse,100*cfg.ImpulseRate,cfg.ImpulseSize, ...
                cfg.Clipping,cfg.ClipLevel,100*cfg.Offset,cfg.Twist);
        end

        function runBenchmark(app)
            if app.Busy, return; end
            first = app.UI.StartSNR.Value; last = app.UI.EndSNR.Value;
            step = app.UI.StepSNR.Value; repeats = round(app.UI.Trials.Value);
            if any(~isfinite([first last step repeats])) || first>last || step<=0
                uialert(app.UIFigure,'Use finite settings, start <= end, and a positive step.', ...
                    'Invalid benchmark settings'); return;
            end
            levels = first:step:last;
            app.UI.Trials.Value = repeats;
            cfg = app.settings(); ctx = app.decoderContext(cfg.Window);
            count = 16*repeats; total = count*numel(levels);
            stream = RandStream('mt19937ar','Seed',12345);
            description = app.configurationText(cfg);
            app.UI.BenchmarkNote.Value = {['RUNNING - real DSP only. ' description], ...
                sprintf('%d frames/SNR; seed 12345. Timing excludes synthesis, UI and setup.',count)};
            dialog = uiprogressdlg(app.UIFigure,'Title','Paired decoder benchmark', ...
                'Message','Preparing decoders...','Cancelable','on','Value',0);
            app.Busy = true; app.StopRequested = false; app.UI.Run.Enable = 'off';
            cleanup = onCleanup(@() app.finishBenchmark(dialog)); %#ok<NASGU>
            cla(app.UI.RateAxes); cla(app.UI.TimingAxes);
            app.UI.Results.Data = [];
            data = zeros(0,10); done = 0; canceled = false;
            try
                % Warm up both paths before measuring; all frames are paired.
                random = app.randomFrame(stream,true);
                x = app.channel(1,1,20,cfg,random);
                app.decodeDTMF(x,'FFT',ctx); app.decodeDTMF(x,'Goertzel',ctx);
                for levelIndex = 1:numel(levels)
                    counts = zeros(2,3); timings = nan(count,2);
                    keys = repmat(1:16,1,repeats);
                    keys = keys(randperm(stream,count));
                    used = 0;
                    for trial = 1:count
                        if mod(trial-1,8)==0
                            dialog.Value = done/total;
                            dialog.Message = sprintf('SNR %.1f dB | %d / %d frames', ...
                                levels(levelIndex),done,total);
                            drawnow;
                            if app.StopRequested || dialog.CancelRequested
                                canceled = true; break;
                            end
                        end
                        [r,c] = ind2sub([4 4],keys(trial));
                        truth = app.KeyMap(r,c);
                        random = app.randomFrame(stream,true);
                        x = app.channel(r,c,levels(levelIndex),cfg,random);
                        % Alternate measurement order to reduce order bias.
                        if mod(trial,2)==1
                            [fr,ft] = app.timedDecode(x,'FFT',ctx);
                            [gr,gt] = app.timedDecode(x,'Goertzel',ctx);
                        else
                            [gr,gt] = app.timedDecode(x,'Goertzel',ctx);
                            [fr,ft] = app.timedDecode(x,'FFT',ctx);
                        end
                        results = {fr,gr}; used = used+1; done = done+1;
                        timings(used,:) = [ft gt];
                        for method = 1:2
                            result = results{method};
                            if ~result.Valid, category = 3;
                            elseif result.Key==truth, category = 1;
                            else, category = 2;
                            end
                            counts(method,category) = counts(method,category)+1;
                        end
                    end
                    if used>0
                        rates = 100*counts/used;
                        data(end+1,:) = [levels(levelIndex) used rates(1,:) ...
                            rates(2,:) 1e6*median(timings(1:used,:),1)]; %#ok<AGROW>
                        app.plotBenchmark(data);
                    end
                    if canceled, break; end
                end
                state = 'COMPLETE';
                if canceled, state = 'CANCELED (completed frames retained)'; end
                app.UI.BenchmarkNote.Value = {[state ' - ' description], ...
                    sprintf(['%d actual frames; seed 12345. Shared confidence gates; ' ...
                    'FFT also checks peak frequency. Times are implementation-specific.'],done)};
                app.UI.Status.Text = sprintf('Benchmark %s: %d paired frames tested.',lower(state),done);
            catch ME
                app.UI.BenchmarkNote.Value = {'Benchmark stopped; completed results retained.',ME.message};
                if ~app.CloseAfterBenchmark
                    uialert(app.UIFigure,ME.message,'Benchmark error');
                end
            end
        end

        function [result,elapsed] = timedDecode(app,x,method,ctx)
            % Three executions per frame reduce timer jitter. This includes
            % windowing, spectral analysis, confidence gates and key matching.
            elapsed = zeros(1,3);
            for k = 1:3
                timer = tic; result = app.decodeDTMF(x,method,ctx);
                elapsed(k) = toc(timer);
            end
            elapsed = median(elapsed);
        end

        function plotBenchmark(app,data)
            ax = app.UI.RateAxes; cla(ax); hold(ax,'on');
            colors = [0.02 0.55 0.35;0.85 0.2 0.25;0.9 0.58 0.06];
            names = {'Correct','Incorrect','Rejected'};
            for k = 1:3
                plot(ax,data(:,1),data(:,2+k),'-o','Color',colors(k,:), ...
                    'LineWidth',1.6,'MarkerSize',4,'DisplayName',['FFT ' names{k}]);
                plot(ax,data(:,1),data(:,5+k),'--s','Color',colors(k,:), ...
                    'LineWidth',1.6,'MarkerSize',4,'DisplayName',['Goertzel ' names{k}]);
            end
            hold(ax,'off'); ylim(ax,[0 100]); grid(ax,'on');
            legend(ax,'Location','best','FontSize',9);
            ax = app.UI.TimingAxes; cla(ax); hold(ax,'on');
            plot(ax,data(:,1),data(:,9),'-o','LineWidth',1.6,'DisplayName','FFT');
            plot(ax,data(:,1),data(:,10),'--s','LineWidth',1.6,'DisplayName','Goertzel');
            hold(ax,'off'); grid(ax,'on'); legend(ax,'Location','best');
            app.UI.Results.Data = data;
        end

        function finishBenchmark(app,dialog)
            if isvalid(dialog), close(dialog); end
            app.Busy = false;
            if isvalid(app.UIFigure)
                app.UI.Run.Enable = 'on';
                if app.CloseAfterBenchmark, delete(app); end
            end
        end

        function closeRequested(app)
            if app.Busy
                app.StopRequested = true; app.CloseAfterBenchmark = true;
            else
                delete(app);
            end
        end
    end

    methods (Access = public)
        function app = DTMF_App_finalized
            app.Time = (0:round(app.Fs*app.ToneDuration)-1)'/app.Fs;
            app.createComponents();
            registerApp(app,app.UIFigure);
            app.UIFigure.Visible = 'on';
            if nargout==0, clear app; end
        end

        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end
end