%% AY Last Edit 05-01-26
% Notes: 05-01-26 - Interpolates photometry gaps (linear) to improve de-jittered average

%%
close all;
clear;

nChan = 3; %number of acquisition channels
photo_Chan = 3;
photo_start = 100; %ms
photo_length = 2200; %ms
photo_gap = 100; %ms (100)
%photo_count = 8;

stim_start = 1000; %ms (1000)
jitter_length = 100; %ms

red_freq = 50; %Hz reduced frequency for output (50)

% Import an AxoGraph X chart
[data, hd] = importaxographx();

acq_freq = 1 / (data(end, 1) / size(data, 1));
nSweeps = (size(data, 2) - 1) / nChan;

data_time = data(:, 1); % first column time data
photo_count = floor((size(data, 1) / acq_freq * 1000 - photo_start) / (photo_length + photo_gap));

%for i = 1 : size(data, 2) - 1
%    plot(data_time, data(:, i));
%    hold on;
%end
%hold off;

for i = 1 : nSweeps
   data_photo(:, i) = data(:, 1 + i * nChan); % separates photometry traces from [data]
end

%for i = 1 : size(data_photo, 2)
%    plot(data_time, data_photo(:, i));
%    hold on;
%end
%hold off;

% Normalize data (∆F/F0)
for i = 1: size(data_photo, 2)
    f0 = mean(data_photo((stim_start - 200) / 1000 * acq_freq : stim_start / 1000 * acq_freq, i)); % f0 = mean(data_photo((photo_start + 20) / 1000 * acq_freq : stim_start / 1000 * acq_freq, i));
    data_photo_norm(:, i) = (data_photo(:, i) - f0) / f0;
end

%for i = 1 : size(data_photo_norm, 2)
%    plot(data_time, data_photo_norm(:, i));
%    hold on;
%end
%hold off;

% Set times when shutter is off (i.e. between photometry periods) to NaN
for i = 1 : size(data_photo_norm, 2) % Loops each photometry trace
    
    data_photo_norm(1 : (photo_start + 20) / 1000 * acq_freq, i) = NaN; %start of recording to photo_start
    
    for j = 1 : photo_count - 1
        % data_photo_norm((photo_start + j * photo_length + (j - 1) * photo_gap - 20) / 1000 * acq_freq : (photo_start + j * photo_length + (j - 1) * photo_gap + photo_gap + 20) / 1000 * acq_freq, i) = NaN;
        
        % interpolates between photometry pulses
        x1 = round((photo_start + j * photo_length + (j - 1) * photo_gap - 50) / 1000 * acq_freq);
        x2 = round((photo_start + j * photo_length + (j - 1) * photo_gap) / 1000 * acq_freq);
        x_start = (x1 + x2) / 2;
              
        y_start = mean(data_photo_norm(x1 : x2, i));
        
        x3 = round((photo_start + j * photo_length + j * photo_gap + 50) / 1000 * acq_freq);
        x4 = round((photo_start + j * photo_length + j * photo_gap + 100) / 1000 * acq_freq);
        x_end = (x3 + x4) / 2;
              
        y_end = mean(data_photo_norm(x3 : x4, i));
        
        m = (y_end - y_start) / (x_end - x_start); % gradient across x_start to x_end
        c = y_start - (x_start * m); % constant;
        
        for k = x_start : x_end
            data_photo_norm(k, i) = m * k + c;
        end
        
        % y_start = mean(data_photo_norm(photo_start + j * photo_length + (j - 1) * photo_gap - 20) / 1000 * acq_freq : (photo_start + j * photo_length + (j - 1) * photo_gap) / 1000 * acq_freq, i);      
        
        %x_start = (photo_start + j * photo_length + (j - 1) * photo_gap - 10) / 1000 * acq_freq;
        %y_end = mean(data_photo_norm(photo_start + j * photo_length + j * photo_gap + 20) / 1000 * acq_freq) : data_photo_norm(photo_start + j * photo_length + j * photo_gap + 40) / 1000 * acq_freq;
        %x_end = data_photo_norm(photo_start + j * photo_length + j * photo_gap + 30) / 1000 * acq_freq;
        %data_photo_norm(photo_start + j * photo_length + (j - 1) * photo_gap - 20) / 1000 * acq_freq = (y_end - y_start) / (x_end - x_start) * i;
    end
       
    data_photo_norm((photo_start + photo_count * photo_length + (photo_count - 1) * photo_gap - 20) / 1000 * acq_freq : end, i) = NaN;
end

i = 1;
exclude_sweeps = [];
while i <= size(data_photo_norm, 2)
    if any(exclude_sweeps == i)
        color = 'red';
    else
        color = 'black';
    end
    plot(data_time, data_photo_norm(:, i), color);
    title("Photometry Sweep #" + num2str(i), "[<] Previous, [>] Next, [X] Exclude, [Q] to Exit");
    w = waitforbuttonpress;
    
    if w == 1
        keyPressed = get(gcf, 'CurrentCharacter');
        if strcmpi(keyPressed, ',')
            i = i - 1;
            if i < 1
                i = 1;
            end
        end    
        if strcmpi(keyPressed, '.')
            i = i + 1;
            if i >= size(data_photo_norm, 2)
                i = size(data_photo_norm, 2);
            end     
        end
        if strcmpi(keyPressed, 'x')
            i = i;
            if ~any(exclude_sweeps == i)
                exclude_sweeps = [exclude_sweeps, i];
            elseif any(exclude_sweeps == i)
                exclude_sweeps(exclude_sweeps == i) = [];
            end
        end    
        if strcmpi(keyPressed, 'q')
            i = size(data_photo_norm, 2) + 1;
        end
    end
end

% Exclude sweeps
for i = 1 : size(data_photo_norm, 2)
    if find(exclude_sweeps == i) ~= 0
        data_photo_norm(:, i) = NaN;
    end
end

% DeJitter normalized photometry data
for i = 1 : size(data_photo_norm, 2)
    if mod(i, 2) == 1 %odd sweeps
        data_photo_norm_dejit(:, i) = data_photo_norm(1 : end - (jitter_length / 1000 * acq_freq), i);
    else %even sweeps
        data_photo_norm_dejit(:, i) = data_photo_norm((jitter_length / 1000 * acq_freq) + 1 : end, i);
    end
end
data_time_dejit = data_time(1 : end - (jitter_length / 1000 * acq_freq));


%for i = 1 : size(data_photo_norm_dejit, 2)
%    plot(data_time_dejit, data_photo_norm_dejit(:, i));
%    hold on;
%end
%hold off;

% Calculates mean of dejittered (normalized) photometry data
mean_data_photo_norm_dejit = mean(data_photo_norm_dejit, 2, "omitnan");

data_time_red = [];
mean_data_photo_red = [];

for i = 1 : size(data_time_dejit, 1) / (acq_freq / red_freq)

    data_time_red = [data_time_red, mean(data_time_dejit((i - 1) * (acq_freq / red_freq) + 1 : i * (acq_freq / red_freq)))];
    mean_data_photo_red = [mean_data_photo_red, mean(mean_data_photo_norm_dejit((i - 1) * (acq_freq / red_freq) + 1 : i * (acq_freq / red_freq)))];

end

output_data = [data_time_red', mean_data_photo_red'];

plot(output_data(:, 1), output_data(:, 2));
title('Averaged Normalized DeJittered Photometry Data');