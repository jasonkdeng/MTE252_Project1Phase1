function results = MTE252_Project(inputFiles, phase, cfg)
% MTE252_PROJECT Cochlear implant audio processor, Phases 1-3.
% Requires MATLAB R2016b+ and Signal Processing Toolbox.
%
% Run with no arguments to select audio files and complete Phase 1:
%   MTE252_Project
% Run the complete processor:
%   results = MTE252_Project({'male.wav','female.wav'}, 3);
% Change a design parameter for Phase 3 comparisons:
%   cfg = struct('numChannels',16,'spacing','log','designName','N16_log');
%   results = MTE252_Project({'male.wav'},3,cfg);
% phase = 1: Task 3; phase = 2: Tasks 3-9 (no test tone);
% phase = 3: Tasks 3-13 (no test tone).
% Tasks 1-2 and human listening evaluations in Tasks 14-16 are not automated.
% Outputs go into output/<designName>/<clipName>/ under the current folder.
%
% Important PDF clarifications:
% - Task 3.7 specifies 1 kHz; the 200 Hz reference in Task 10 is a typo.
% - Modulate using the smoothed envelopes from Task 8 (see the schematic).
% - At Fs=16 kHz, 8 kHz is Nyquist. The last channel is a high-pass
%   filter extending to Nyquist, avoiding an invalid cutoff exactly at 1.

if nargin < 2 || isempty(phase), phase = 1; end
if nargin < 3 || isempty(cfg), cfg = struct(); end
validateattributes(phase, {'numeric'}, {'scalar','integer','>=',1,'<=',3});
cfg = settings(cfg);
if nargin < 1 || isempty(inputFiles)
    [names, folder] = uigetfile({'*.wav;*.flac;*.mp3;*.m4a','Audio files'}, ...
        'Select project recordings', 'MultiSelect','on');
    if isequal(names,0), results = struct([]); return; end
    if ischar(names), names = {names}; end
    inputFiles = cellfun(@(s) fullfile(folder,s),names,'UniformOutput',false);
elseif ischar(inputFiles)
    inputFiles = {inputFiles};
elseif isstring(inputFiles)
    inputFiles = cellstr(inputFiles);
end
assert(iscell(inputFiles) && ~isempty(inputFiles),'Provide one or more audio paths.');
assert(exist('resample','file') ~= 0,'Signal Processing Toolbox is required.');
results = struct([]);

for fileIndex = 1:numel(inputFiles)
    inputPath = char(inputFiles{fileIndex});
    [~,clipName] = fileparts(inputPath);
    % Index prevents two files with identical names overwriting each other.
    clipFolder = fullfile(cfg.outputFolder,cfg.designName, ...
        sprintf('%02d_%s',fileIndex,clipName));
    if ~exist(clipFolder,'dir'), mkdir(clipFolder); end

    %% Phase 1: read, inspect channels, resample, play, write, and plot.
    % Task 3.1
    [audio, originalFs] = audioread(inputPath);
    assert(~isempty(audio) && all(isfinite(audio(:))), ...
        'Input audio must be nonempty and finite.');
    fprintf('\n%s: Fs = %g Hz, %d channel(s), %.2f seconds\n', ...
        inputPath,originalFs,size(audio,2),size(audio,1)/originalFs);
    assert(originalFs >= cfg.Fs, ...
        'Sampling rate is below 16 kHz. Use a new recording, as advised in Task 3.6.');
    if size(audio,1)/originalFs > 30
        warning('Recording exceeds the recommended 30 seconds; it is not truncated.');
    end
    % Task 3.2: sum stereo columns as explicitly requested (not an average).
    if size(audio,2) == 2
        x = audio(:,1) + audio(:,2);
    elseif size(audio,2) == 1
        x = audio;
    else
        error('Only mono or stereo input is supported.');
    end
    % Task 3.6: resample includes anti-alias filtering.
    if originalFs ~= cfg.Fs
        [p,q] = rat(cfg.Fs/originalFs);
        x = resample(x,p,q);
    end
    % Preserve the stereo sum in memory. Apply one scalar gain only if
    % needed for WAV storage/playback, avoiding clipping of summed channels.
    x = x(:);
    inputGain = 1/max(1,max(abs(x)));
    x = x*inputGain;
    Fs = cfg.Fs;
    n = (0:numel(x)-1)';
    t = n/Fs;
    % Tasks 3.3-3.4
    playAudio(x,Fs,cfg.playAudio,'Resampled mono input');
    audiowrite(fullfile(clipFolder,'input_mono_16k.wav'),x,Fs);
    % Task 3.5
    fig = figure('Visible',cfg.figureVisible,'Name','Task 3.5');
    plot(n,x); xlabel('Sample number n'); ylabel('Amplitude');
    title('Input waveform at 16 kHz'); grid on;
    saveas(fig,fullfile(clipFolder,'task3_5_input_waveform.png'));
    if ~cfg.keepFigures, close(fig); end

    if phase == 1
        % Task 3.7: automatically skipped for Phases 2 and 3.
        tone = cos(2*pi*1000*t);
        playAudio(cfg.playbackGain*tone,Fs,cfg.playAudio,'1 kHz cosine');
        audiowrite(fullfile(clipFolder,'task3_7_cosine_1kHz.wav'),tone,Fs);
        fig = figure('Visible',cfg.figureVisible,'Name','Task 3.7');
        % Include the endpoint at 2 ms to show two complete cycles.
        count = min(numel(tone),round(2*Fs/1000)+1);
        plot(t(1:count)*1000,tone(1:count),'-o');
        xlabel('Time (ms)'); ylabel('Amplitude');
        title('Two cycles of a 1 kHz cosine'); grid on;
        saveas(fig,fullfile(clipFolder,'task3_7_two_cycles.png'));
        if ~cfg.keepFigures, close(fig); end
    end

    result = struct('inputFile',inputPath,'originalFs',originalFs, ...
        'Fs',Fs,'inputGain',inputGain,'input',x,'output',[], ...
        'bandEdgesHz',[],'carrierHz',[],'folder',clipFolder);
    if phase >= 2
        %% Phase 2: Tasks 4-9.
        if strcmpi(cfg.spacing,'log')
            edges = logspace(log10(100),log10(Fs/2),cfg.numChannels+1);
            edges([1 end]) = [100 Fs/2];
            centers = sqrt(edges(1:end-1).*edges(2:end));
        else
            edges = linspace(100,Fs/2,cfg.numChannels+1);
            centers = (edges(1:end-1)+edges(2:end))/2;
        end
        filtered = zeros(numel(x),cfg.numChannels);
        envelopes = zeros(size(filtered));
        [lpB,lpA] = makeFilter(cfg.filterType,cfg.envelopeOrder, ...
            cfg.envelopeCutoff/(Fs/2),'low');
        for k = 1:cfg.numChannels
            % overlap is a fraction of each original band's width added
            % on EACH side, clipped to the 100 Hz-Nyquist range.
            width = edges(k+1)-edges(k);
            lo = max(100,edges(k)-cfg.overlap*width);
            hi = min(Fs/2,edges(k+1)+cfg.overlap*width);
            if hi >= Fs/2
                [b,a] = makeFilter(cfg.filterType,cfg.bandOrder,lo/(Fs/2),'high');
            else
                [b,a] = makeFilter(cfg.filterType,cfg.bandOrder, ...
                    [lo hi]/(Fs/2),'bandpass');
            end
            % Causal filtering, with zero initial conditions.
            filtered(:,k) = filter(b,a,x);                  % Task 5
            rectified = abs(filtered(:,k));                 % Task 7
            envelopes(:,k) = filter(lpB,lpA,rectified);      % Task 8
        end
        assert(all(isfinite(envelopes(:))), ...
            'Nonfinite filter output: check filter order and bandwidth.');
        plotChannels(t,filtered,'Band-pass output','task6_channels.png',clipFolder,cfg);
        plotChannels(t,envelopes,'Extracted envelope','task9_envelopes.png',clipFolder,cfg);
        result.bandEdgesHz = edges;
        result.carrierHz = centers;
        % Keep the large intermediate matrices on disk for report plots.
        save(fullfile(clipFolder,'phase2_signals.mat'), ...
            'filtered','envelopes','edges','centers','Fs','cfg','-v7.3');

        if phase == 3
            %% Phase 3: Tasks 10-13.
            y = zeros(size(x));
            for k = 1:cfg.numChannels
                carrier = cos(2*pi*centers(k)*t);            % Task 10
                modulated = envelopes(:,k).*carrier;        % Task 11
                y = y + modulated;                         % Task 12
            end
            assert(all(isfinite(y)),'Nonfinite synthesized output.');
            peak = max(abs(y));
            if peak > 0, y = y/peak; end  % Silence stays zero (no 0/0).
            % Peak normalization here follows Task 12; it is NOT perceptual
            % loudness matching. Match loudness separately for questionnaires.
            audiowrite(fullfile(clipFolder,'processed_output.wav'),y,Fs);
            playAudio(cfg.playbackGain*y,Fs,cfg.playAudio,'Synthesized output');
            result.output = y;
        end
    end
    results(fileIndex) = result; %#ok<AGROW>
    save(fullfile(clipFolder,'run_settings.mat'),'cfg','phase','originalFs','inputGain');
    fprintf('Saved results to: %s\n',clipFolder);
end
end

function cfg = settings(cfg)
% Edit these defaults, or pass a struct with just the fields to override.
defaults = struct('Fs',16000,'numChannels',8,'spacing','log', ...
    'filterType','butter','bandOrder',4,'envelopeOrder',4, ...
    'envelopeCutoff',400,'overlap',0,'playAudio',true, ...
    'playbackGain',0.5,'figureVisible','on','keepFigures',true, ...
    'outputFolder',fullfile(pwd,'output'),'designName','baseline');
names = fieldnames(cfg);
assert(all(ismember(names,fieldnames(defaults))),'Unknown configuration field.');
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(cfg,names{i}), cfg.(names{i}) = defaults.(names{i}); end
end
assert(cfg.Fs == 16000,'Project sampling rate must be 16 kHz.');
validateattributes(cfg.numChannels,{'numeric'},{'scalar','integer','>=',2});
validateattributes(cfg.bandOrder,{'numeric'},{'scalar','integer','positive'});
validateattributes(cfg.envelopeOrder,{'numeric'},{'scalar','integer','positive'});
validateattributes(cfg.envelopeCutoff,{'numeric'},{'scalar','>',0,'<',8000});
validateattributes(cfg.overlap,{'numeric'},{'scalar','>=',0,'<=',0.5});
validateattributes(cfg.playbackGain,{'numeric'},{'scalar','>',0,'<=',1});
assert(any(strcmpi(cfg.spacing,{'linear','log'})),'Use linear or log spacing.');
assert(any(strcmpi(cfg.filterType,{'butter','fir'})),'Use butter or fir filters.');
assert(~isempty(regexp(char(cfg.designName),'^[A-Za-z0-9_-]+$','once')), ...
    'designName must contain only letters, digits, underscores, or hyphens.');
if strcmpi(cfg.filterType,'fir')
    assert(mod(cfg.bandOrder,2)==0 && mod(cfg.envelopeOrder,2)==0, ...
        'Use even orders for FIR filters. Try bandOrder=256 and envelopeOrder=128.');
end
end

function [b,a] = makeFilter(kind,order,cutoff,response)
% Butterworth band-pass order is 2*order; low/high-pass order is order.
% FIR order is the supplied order for all response types.
if strcmpi(kind,'butter')
    [b,a] = butter(order,cutoff,response);
else
    b = fir1(order,cutoff,response);
    a = 1;
end
end

function playAudio(x,Fs,enabled,label)
if enabled
    fprintf('Playing: %s\n',label);
    player = audioplayer(x,Fs);
    playblocking(player);
end
end

function plotChannels(t,signals,label,filename,folder,cfg)
fig = figure('Visible',cfg.figureVisible,'Name',label);
channels = [1 size(signals,2)];
for j = 1:2
    subplot(2,1,j);
    plot(t,signals(:,channels(j)));
    xlabel('Time (s)'); ylabel('Amplitude'); grid on;
    title(sprintf('%s: channel %d',label,channels(j)));
end
saveas(fig,fullfile(folder,filename));
if ~cfg.keepFigures, close(fig); end
end
