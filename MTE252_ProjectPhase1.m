%% MTE 252 Project - Cochlear implant signal processing
% Requires Signal Processing Toolbox.
% Select a recording when prompted. Run again for each recording/design.
% phase 1: Task 3; phase 2: Tasks 3-9; phase 3: Tasks 3-13.
% Listening evaluations (Tasks 14-16) must be completed separately.
clear; close all; clc;

%% Settings
phase = 1;
N = 8;                      % Number of frequency channels
spacing = 'log';             % 'log' or 'linear'
bandOrder = 4;               % Butterworth band-pass order is 2*bandOrder
lowpassOrder = 4;
envelopeCutoff = 400;        % Hz
playAudio = true;            % Set false to skip playback
outputFolder = 'results';    % Change for each design to keep previous results

%% Task 3.1: Read an audio file and obtain its sampling rate
[file, folder] = uigetfile({'*.wav;*.mp3;*.flac;*.m4a','Audio files'});
if isequal(file, 0), return; end
[x, Fs] = audioread(fullfile(folder, file));
fprintf('Original sampling rate: %g Hz\n', Fs);

%% Task 3.2: Convert stereo to mono by adding the two columns
if size(x, 2) == 2
    x = x(:, 1) + x(:, 2);
elseif size(x, 2) ~= 1
    error('Use a mono or stereo recording.');
end

%% Task 3.6: Resample to 16 kHz before further processing
if Fs < 16000
    error('Use a recording with a sampling rate of at least 16 kHz.');
elseif Fs ~= 16000
    x = resample(x, 16000, Fs);
end
Fs = 16000;
% Avoid clipping when the two stereo channels have been added.
if max(abs(x)) > 1
    x = x / max(abs(x));
end
n = (0:length(x)-1)';
t = n / Fs;
[~, name] = fileparts(file);
outputFolder = fullfile(outputFolder, name);
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end

%% Tasks 3.3 and 3.4: Play and save the mono input
if playAudio
    sound(x, Fs);
    pause(length(x)/Fs + 0.5);
end
audiowrite(fullfile(outputFolder, 'input_16k.wav'), x, Fs);

%% Task 3.5: Plot the input against sample number
figure;
plot(n, x);
xlabel('Sample number'); ylabel('Amplitude');
title('Input waveform'); grid on;
saveas(gcf, fullfile(outputFolder, 'input_waveform.png'));

%% Task 3.7: Generate a 1 kHz cosine (Phase 1 only)
if phase == 1
    tone = cos(2*pi*1000*t);
    if playAudio
        sound(0.5*tone, Fs);
        pause(length(tone)/Fs + 0.5);
    end
    figure;
    samples = 1:min(length(tone), 33); % 0 to 2 ms: two cycles at 16 kHz
    plot(t(samples), tone(samples), '-o');
    xlabel('Time (s)'); ylabel('Amplitude');
    title('Two cycles of a 1 kHz cosine'); grid on;
    saveas(gcf, fullfile(outputFolder, 'cosine_two_cycles.png'));
end

if phase >= 2
    %% Task 4: Define the frequency bands
    if strcmp(spacing, 'log')
        edges = logspace(log10(100), log10(8000), N+1);
    else
        edges = linspace(100, 8000, N+1);
    end
    filtered = zeros(length(x), N);
    envelopes = zeros(length(x), N);
    [bLP, aLP] = butter(lowpassOrder, envelopeCutoff/(Fs/2), 'low');

    for k = 1:N
        % At 16 kHz, 8 kHz is Nyquist and cannot be a butter cutoff.
        % The last channel uses a high-pass filter up to Nyquist instead.
        if k == N
            [b, a] = butter(bandOrder, edges(k)/(Fs/2), 'high');
        else
            [b, a] = butter(bandOrder, edges(k:k+1)/(Fs/2), 'bandpass');
        end
        %% Tasks 5, 7 and 8: Filter, rectify, and smooth each channel
        filtered(:, k) = filter(b, a, x);
        rectified = abs(filtered(:, k));
        envelopes(:, k) = filter(bLP, aLP, rectified);
    end

    %% Task 6: Plot the lowest and highest frequency channels
    figure;
    subplot(2,1,1); plot(t, filtered(:,1));
    title('Lowest frequency channel'); xlabel('Time (s)'); ylabel('Amplitude');
    subplot(2,1,2); plot(t, filtered(:,N));
    title('Highest frequency channel'); xlabel('Time (s)'); ylabel('Amplitude');
    saveas(gcf, fullfile(outputFolder, 'filtered_channels.png'));

    %% Task 9: Plot their extracted envelopes
    figure;
    subplot(2,1,1); plot(t, envelopes(:,1));
    title('Lowest channel envelope'); xlabel('Time (s)'); ylabel('Amplitude');
    subplot(2,1,2); plot(t, envelopes(:,N));
    title('Highest channel envelope'); xlabel('Time (s)'); ylabel('Amplitude');
    saveas(gcf, fullfile(outputFolder, 'envelopes.png'));
end

if phase == 3
    %% Tasks 10-12: Generate carriers, modulate, and sum
    y = zeros(size(x));
    for k = 1:N
        if strcmp(spacing, 'log')
            fc = sqrt(edges(k)*edges(k+1));
        else
            fc = (edges(k)+edges(k+1))/2;
        end
        carrier = cos(2*pi*fc*t);
        y = y + envelopes(:,k).*carrier;
    end
    if max(abs(y)) > 0       % Avoid dividing by zero for silent input
        y = y / max(abs(y));
    end

    %% Task 13: Play and save the synthesized output
    if playAudio
        sound(0.5*y, Fs);
        pause(length(y)/Fs + 0.5);
    end
    audiowrite(fullfile(outputFolder, 'processed_output.wav'), y, Fs);
end
