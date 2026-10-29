clear; close all; clc;

%% 3.1: Read the audio file and obtain its sampling rate
[x, Fs] = audioread('input.wav'); % Replace with your filename
fprintf('Sampling rate: %g Hz\n', Fs);

%% 3.2: Convert stereo to mono
if size(x, 2) == 2
    x = x(:, 1) + x(:, 2);
end

%% 3.6: Resample to 16 kHz before playback and plotting
if Fs < 16000
    error('Choose a recording sampled at 16 kHz or higher.');
elseif Fs ~= 16000
    x = resample(x, 16000, Fs);
end
Fs = 16000;

% Prevent clipping after adding stereo channels
if max(abs(x)) > 1
    x = x / max(abs(x));
end

%% 3.3: Play the audio
sound(x, Fs);
pause(length(x)/Fs + 0.5);

%% 3.4: Save the audio to a new file
audiowrite('output.wav', x, Fs);

%% 3.5: Plot the waveform against sample number
n = (0:length(x)-1)';

figure;
plot(n, x);
xlabel('Sample number');
ylabel('Amplitude');
title('Input waveform');

%% 3.7: Generate and play a 1 kHz cosine
t = n/Fs;
tone = cos(2*pi*1000*t);

sound(tone, Fs);

% Plot two complete cycles: 0 to 2 ms
figure;
plot(t(1:33), tone(1:33), '-o');
xlabel('Time (s)');
ylabel('Amplitude');
title('Two cycles of a 1 kHz cosine');